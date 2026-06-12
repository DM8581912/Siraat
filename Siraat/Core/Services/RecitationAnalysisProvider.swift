import Foundation

enum RecitationAnalysisEngine: String, Codable {
    case localMatcher
    case coreML

    var displayName: String {
        switch self {
        case .localMatcher: "Word follow‑along (beta)"
        case .coreML: "On‑device Tajweed analysis"
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
