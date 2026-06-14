import Combine
import Foundation

/// One finalized sentence of the khutba: the recognized Arabic plus its translation
/// (nil until the on-device translator fills it in).
struct LiveSegment: Identifiable, Equatable, Codable, Hashable {
    let id: UUID
    let sourceText: String
    var translatedText: String?

    init(id: UUID = UUID(), sourceText: String, translatedText: String? = nil) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
    }
}

@MainActor
final class LiveTranslationViewModel: ObservableObject {
    @Published var targetLanguage: TranslationLanguage = .english
    @Published private(set) var segments: [LiveSegment] = []
    @Published private(set) var partialTranscript = ""
    @Published private(set) var waveformLevel: Double = 0
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    /// A persistent, user-facing notice about the translator itself (downloading the language
    /// model, or it being unavailable for the chosen language). nil while translation proceeds
    /// normally. Distinct from `errorMessage`, which is a one-shot alert.
    @Published var translationNotice: String?

    @Published var didSaveSession = false

    // Owned, not shared: this feature has its own microphone engine.
    private let audioStreamManager = AudioStreamManager()
    private let library = KhutbaLibraryStore()
    private var didConfigure = false

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, h:mm a"
        return formatter
    }()
    private var cancellables = Set<AnyCancellable>()
    private var transcriptSegmenter = TranscriptSegmenter()
    private var seenSources = Set<String>()

    func configure() {
        guard !didConfigure else { return }
        didConfigure = true

        audioStreamManager.$latestSegment
            .compactMap { $0 }
            .sink { [weak self] segment in self?.handle(segment) }
            .store(in: &cancellables)

        audioStreamManager.$waveformLevel
            .assign(to: &$waveformLevel)

        audioStreamManager.$isRecording
            .assign(to: &$isRecording)

        audioStreamManager.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in self?.errorMessage = message }
            .store(in: &cancellables)
    }

    func start() {
        Task {
            do {
                try await audioStreamManager.start(languageIdentifier: "ar-SA")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        audioStreamManager.stop()
        // Flush whatever remains of the last (unterminated) sentence.
        appendSources(transcriptSegmenter.consume(partialTranscript, isFinal: true))
    }

    func clear() {
        segments.removeAll()
        seenSources.removeAll()
        transcriptSegmenter.reset()
        partialTranscript = ""
    }

    var canSaveSession: Bool { !segments.isEmpty }

    /// Saves the captured khutba (Arabic + translations) to the library to revisit later.
    func saveSession() {
        guard canSaveSession else { return }
        let session = KhutbaSession(
            date: Date(),
            title: "Khutba · \(Self.titleFormatter.string(from: Date()))",
            segments: segments
        )
        library.save(session)
        didSaveSession = true
    }

    /// True while any captured sentence still needs translating.
    var hasUntranslated: Bool { segments.contains { $0.translatedText == nil } }

    func setTranslation(_ text: String, for id: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].translatedText = text
    }

    /// Clears translations so they re-run (e.g. after the target language changes).
    func retranslateAll() {
        for index in segments.indices {
            segments[index].translatedText = nil
        }
    }

    private func handle(_ segment: SpeechTranscriptSegment) {
        partialTranscript = segment.text
        appendSources(transcriptSegmenter.consume(segment.text, isFinal: segment.isFinal))
    }

    private func appendSources(_ sources: [String]) {
        for source in sources {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seenSources.contains(trimmed) else { continue }
            seenSources.insert(trimmed)
            segments.append(LiveSegment(sourceText: trimmed))
        }
    }
}
