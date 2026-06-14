import Foundation

enum RecitationAnalysisEngine: String, Codable {
    case localMatcher
    case coreML
    case streamingAlign

    var displayName: String {
        switch self {
        case .localMatcher: "Word follow‑along (beta)"
        case .coreML: "On‑device Tajweed analysis"
        case .streamingAlign: "Live follow‑along (beta)"
        }
    }
}

struct RecitationAnalysisResult: Equatable {
    let words: [RecitationWord]
    let engine: RecitationAnalysisEngine
}

protocol RecitationAnalysisProviding {
    func analyze(transcript: String, expectedWords: [RecitationWord]) async -> RecitationAnalysisResult

    /// Per-character Tajweed feedback for one ayah, driven by on-device forced
    /// alignment of the recorded PCM against the ayah's canonical phonetic blueprint.
    /// Returns `[]` when no blueprint/aligner is available, leaving the word-level
    /// path unaffected. Providers that do not support character analysis inherit the
    /// default empty implementation below.
    func analyzeCharacters(
        uthmani: String,
        blueprint: AyahPhonemeMap,
        samples: [Float],
        sampleRate: Double
    ) async -> [RecitationCharacterResult]
}

extension RecitationAnalysisProviding {
    func analyzeCharacters(
        uthmani: String,
        blueprint: AyahPhonemeMap,
        samples: [Float],
        sampleRate: Double
    ) async -> [RecitationCharacterResult] {
        []
    }
}
