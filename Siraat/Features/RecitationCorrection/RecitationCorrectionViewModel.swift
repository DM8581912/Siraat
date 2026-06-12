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
    @Published var selectedSurah = 1
    @Published var selectedVerseNumber = 1
    @Published var script: QuranScript = .uthmani
    @Published var errorMessage: String?

    private var audioStreamManager: AudioStreamManager?
    private var databaseManager: QuranDatabaseManaging?
    private var correctionService: RecitationCorrectionServicing?
    private var analysisProvider: RecitationAnalysisProviding?
    private var analysisTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

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
        audioStreamManager: AudioStreamManager,
        databaseManager: QuranDatabaseManaging,
        correctionService: RecitationCorrectionServicing,
        analysisProvider: RecitationAnalysisProviding
    ) {
        guard self.audioStreamManager == nil else { return }
        self.audioStreamManager = audioStreamManager
        self.databaseManager = databaseManager
        self.correctionService = correctionService
        self.analysisProvider = analysisProvider

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
    }

    func loadVerse() {
        Task {
            guard let databaseManager else { return }

            do {
                let verses = try await databaseManager.verses(forSurah: selectedSurah, language: .english, reciterID: ReaderSettings.default.selectedReciterID)
                selectedVerse = verses.first(where: { $0.verseNumber == selectedVerseNumber }) ?? verses.first
                if let selectedVerse, let correctionService {
                    words = correctionService.prepareWords(for: selectedVerse, script: script)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func startListening() {
        Task {
            do {
                try await audioStreamManager?.start(languageIdentifier: "ar-SA")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopListening() {
        audioStreamManager?.stop()
    }

    func reset() {
        transcript = ""
        if let selectedVerse, let correctionService {
            words = correctionService.prepareWords(for: selectedVerse, script: script)
        }
    }

    private func evaluate(_ transcript: String) {
        guard let analysisProvider else { return }
        let currentWords = words
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            let result = await analysisProvider.analyze(transcript: transcript, expectedWords: currentWords)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.words = result.words
                self?.analysisEngine = result.engine
            }
        }
    }
}
