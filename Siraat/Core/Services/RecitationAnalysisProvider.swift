import CoreML
import Foundation

enum RecitationAnalysisEngine: String, Codable {
    case localMatcher
    case coreML

    var displayName: String {
        switch self {
        // Honest labels: the local engine is a text follow-along aid, not a tajweed judge.
        // The on-device acoustic model is the seam for real tajweed evaluation (not yet
        // shipping — `CoreMLTajweedModelAdapter` returns nil until a model is bundled), so
        // this label never currently appears to users.
        case .localMatcher: "Word follow‑along (beta)"
        case .coreML: "On‑device tajweed model"
        }
    }
}

struct RecitationAnalysisResult: Equatable {
    let words: [RecitationWord]
    let engine: RecitationAnalysisEngine
}

protocol RecitationAnalysisProviding {
    func analyze(transcript: String, expectedWords: [RecitationWord]) async -> RecitationAnalysisResult
}

final class HybridRecitationAnalysisProvider: RecitationAnalysisProviding {
    private let localMatcher: RecitationCorrectionServicing
    private let coreMLAdapter: CoreMLTajweedModelAdapter

    init(
        localMatcher: RecitationCorrectionServicing = RecitationCorrectionService(),
        coreMLAdapter: CoreMLTajweedModelAdapter = CoreMLTajweedModelAdapter()
    ) {
        self.localMatcher = localMatcher
        self.coreMLAdapter = coreMLAdapter
    }

    func analyze(transcript: String, expectedWords: [RecitationWord]) async -> RecitationAnalysisResult {
        if let coreMLResult = await coreMLAdapter.analyze(transcript: transcript, expectedWords: expectedWords) {
            return RecitationAnalysisResult(words: coreMLResult, engine: .coreML)
        }

        return RecitationAnalysisResult(
            words: localMatcher.evaluate(transcript: transcript, expectedWords: expectedWords),
            engine: .localMatcher
        )
    }
}

final class CoreMLTajweedModelAdapter {
    private let model: MLModel?

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "TajweedPronunciationClassifier", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url)
        } else {
            model = nil
        }
    }

    func analyze(transcript: String, expectedWords: [RecitationWord]) async -> [RecitationWord]? {
        guard model != nil else { return nil }

        // A bundled TajweedPronunciationClassifier model can be connected here
        // once its exact input/output schema is known. Until then, the app keeps
        // real-time feedback functional through the local Quran text matcher.
        return nil
    }
}
