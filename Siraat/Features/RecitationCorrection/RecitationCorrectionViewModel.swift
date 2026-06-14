import Combine
import Foundation

@MainActor
final class RecitationCorrectionViewModel: ObservableObject {
    @Published private(set) var selectedVerse: QuranVerse?
    @Published private(set) var words: [RecitationWord] = []
    @Published private(set) var transcript = ""
    @Published private(set) var waveformLevel: Double = 0
    @Published private(set) var isListening = false
    @Published private(set) var analysisEngine: RecitationAnalysisEngine = .localMatcher
    @Published private(set) var characterResults: [RecitationCharacterResult] = []
    /// Position of the word the reciter is currently on (the streaming alignment head), for the
    /// live karaoke highlight. `nil` when not tracking.
    @Published private(set) var activeWordIndex: Int?
    @Published var showColoredAyah = true
    /// Memorization (hifz) test mode: the verse words are redacted and reveal one by one as the
    /// reciter recites each correctly. On-device, like everything else here.
    @Published var hifzMode = false
    @Published var selectedSurah = 1
    @Published var selectedVerseNumber = 1
    @Published var script: QuranScript = .uthmani
    @Published var errorMessage: String?

    // Owned, not shared: this feature has its own microphone engine.
    private let audioStreamManager = AudioStreamManager()
    private let recitationAudioBuffer = RecitationAudioBuffer()
    private var databaseManager: QuranDatabaseManaging?
    private var correctionService: RecitationCorrectionServicing?
    private var analysisProvider: RecitationAnalysisProviding?
    private var blueprintProvider: PhoneticBlueprintProviding?
    private var currentBlueprint: AyahPhonemeMap?
    private var didConfigure = false
    private var analysisTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Whether the colored ayah may be shown. Requires a blueprint for the verse (today
    /// only the Al-Fatiha placeholder exists). Unverified blueprints are surfaced behind a
    /// prominent "experimental / not graded" banner — safe because the placeholder aligner
    /// only ever emits green (it never fabricates a red/yellow verdict). Before an App
    /// Store release, require `blueprint.source.verified` here so unverified Tajweed data
    /// is never presented as authoritative grading.
    var canShowColoredAyah: Bool {
        currentBlueprint != nil
    }

    var isBlueprintExperimental: Bool {
        guard let blueprint = currentBlueprint else { return false }
        return !blueprint.source.verified
    }

    /// Fraction of the verse confirmed correct so far (0...1), for the follow-along progress bar.
    var followProgress: Double {
        guard !words.isEmpty else { return 0 }
        let confirmed = words.filter { $0.status == .correct }.count
        return Double(confirmed) / Double(words.count)
    }

    var confirmedWordCount: Int {
        words.filter { $0.status == .correct }.count
    }

    /// In hifz mode a word stays hidden until the reciter has confirmed it correct.
    func isWordRevealed(at index: Int) -> Bool {
        guard hifzMode else { return true }
        guard words.indices.contains(index) else { return true }
        return words[index].status == .correct
    }

    var selectedChapter: QuranChapter {
        QuranChapter.chapter(number: selectedSurah)
    }

    var selectedChapterVerseRange: ClosedRange<Int> {
        1...selectedChapter.verseCount
    }

    func selectSurah(_ surah: Int) {
        selectedSurah = surah
        selectedVerseNumber = min(selectedVerseNumber, selectedChapter.verseCount)
        loadVerse()
    }

    func configure(
        databaseManager: QuranDatabaseManaging,
        correctionService: RecitationCorrectionServicing,
        analysisProvider: RecitationAnalysisProviding,
        blueprintProvider: PhoneticBlueprintProviding
    ) {
        guard !didConfigure else { return }
        didConfigure = true
        self.databaseManager = databaseManager
        self.correctionService = correctionService
        self.analysisProvider = analysisProvider
        self.blueprintProvider = blueprintProvider

        // Capture raw PCM for the on-device forced aligner. The closure only copies
        // samples into a thread-safe buffer; audio never leaves the device.
        audioStreamManager.onPCMBuffer = { [recitationAudioBuffer] buffer in
            recitationAudioBuffer.append(buffer)
        }

        audioStreamManager.$latestSegment
            .compactMap { $0?.text }
            .sink { [weak self] text in
                self?.transcript = text
                self?.evaluate(text)
            }
            .store(in: &cancellables)

        audioStreamManager.$waveformLevel
            .assign(to: &$waveformLevel)

        audioStreamManager.$isRecording
            .assign(to: &$isListening)

        // Surface permission/recording errors (e.g. denied microphone) that the
        // manager publishes, so the Listen button doesn't silently do nothing.
        audioStreamManager.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)
    }

    func loadVerse() {
        // A new verse is a new session: clear any confirmed-mistake state so it can't leak
        // across, and drop the karaoke head.
        analysisProvider?.resetSession()
        activeWordIndex = nil
        Task {
            guard let databaseManager else { return }

            do {
                let verses = try await databaseManager.verses(forSurah: selectedSurah, language: .english, reciterID: ReaderSettings.default.selectedReciterID)
                selectedVerse = verses.first(where: { $0.verseNumber == selectedVerseNumber }) ?? verses.first
                if let selectedVerse, let correctionService {
                    words = correctionService.prepareWords(for: selectedVerse, script: script)
                }
                currentBlueprint = selectedVerse.map { blueprintProvider?.blueprint(forVerseKey: $0.verseKey) } ?? nil
                characterResults = []
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func startListening() {
        recitationAudioBuffer.reset()
        Task {
            do {
                try await audioStreamManager.start(languageIdentifier: "ar-SA")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopListening() {
        audioStreamManager.stop()
    }

    func reset() {
        transcript = ""
        characterResults = []
        activeWordIndex = nil
        analysisProvider?.resetSession()
        recitationAudioBuffer.reset()
        if let selectedVerse, let correctionService {
            words = correctionService.prepareWords(for: selectedVerse, script: script)
        }
    }

    private func evaluate(_ transcript: String) {
        guard let analysisProvider else { return }
        let currentWords = words
        let blueprint = currentBlueprint
        let uthmani = selectedVerse?.textUthmani ?? ""
        let allowCharacterColoring = canShowColoredAyah
        let audio = recitationAudioBuffer.snapshot()
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            let result = await analysisProvider.analyze(transcript: transcript, expectedWords: currentWords)

            var characters: [RecitationCharacterResult] = []
            if allowCharacterColoring, let blueprint, !uthmani.isEmpty {
                characters = await analysisProvider.analyzeCharacters(
                    uthmani: uthmani,
                    blueprint: blueprint,
                    samples: audio.samples,
                    sampleRate: audio.sampleRate
                )
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.words = result.words
                self?.analysisEngine = result.engine
                self?.activeWordIndex = result.activeWordIndex
                self?.characterResults = characters
            }
        }
    }
}
