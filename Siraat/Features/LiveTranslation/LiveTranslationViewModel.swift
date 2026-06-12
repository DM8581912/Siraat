import Combine
import Foundation

@MainActor
final class LiveTranslationViewModel: ObservableObject {
    @Published var targetLanguage: TranslationLanguage = .english
    @Published private(set) var translationSegments: [TranslationSegment] = []
    @Published private(set) var partialTranscript = ""
    @Published private(set) var waveformLevel: Double = 0
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    // Owned, not shared: this feature has its own microphone engine.
    private let audioStreamManager = AudioStreamManager()
    private var translationService: TranslationServicing?
    private var didConfigure = false
    private var cancellables = Set<AnyCancellable>()
    private var translatedSources = Set<String>()
    private var transcriptSegmenter = TranscriptSegmenter()

    func configure(translationService: TranslationServicing) {
        guard !didConfigure else { return }
        didConfigure = true
        self.translationService = translationService

        audioStreamManager.$latestSegment
            .compactMap { $0 }
            .sink { [weak self] segment in
                self?.handle(segment)
            }
            .store(in: &cancellables)

        audioStreamManager.$waveformLevel
            .assign(to: &$waveformLevel)

        audioStreamManager.$isRecording
            .assign(to: &$isRecording)

        audioStreamManager.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.errorMessage = message
            }
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
        Task { await translateIfNeeded(partialTranscript) }
    }

    func clear() {
        translationSegments.removeAll()
        translatedSources.removeAll()
        transcriptSegmenter.reset()
        partialTranscript = ""
    }

    private func handle(_ segment: SpeechTranscriptSegment) {
        partialTranscript = segment.text
        let sources = transcriptSegmenter.consume(segment.text, isFinal: segment.isFinal)
        for source in sources {
            Task { await translateIfNeeded(source) }
        }
    }

    private func translateIfNeeded(_ source: String) async {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !translatedSources.contains(source), let translationService else { return }

        do {
            let translated = try await translationService.translate(source, to: targetLanguage)
            translatedSources.insert(source)
            translationSegments.append(
                TranslationSegment(sourceText: source, translatedText: translated, targetLanguage: targetLanguage)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
