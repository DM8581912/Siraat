import Foundation

final class HybridRecitationAnalysisProvider: RecitationAnalysisProviding {
    private let localMatcher: RecitationCorrectionServicing
    private let acousticAnalyzer: TajweedAcousticAnalyzing
    private let rulesEngine: TajweedRulesEngine

    init(
        localMatcher: RecitationCorrectionServicing = RecitationCorrectionService(),
        acousticAnalyzer: TajweedAcousticAnalyzing = CoreMLTajweedAcousticAnalyzer(),
        rulesEngine: TajweedRulesEngine = TajweedRulesEngine()
    ) {
        self.localMatcher = localMatcher
        self.acousticAnalyzer = acousticAnalyzer
        self.rulesEngine = rulesEngine
    }

    func analyze(transcript: String, expectedWords: [RecitationWord]) async -> RecitationAnalysisResult {
        var alignedWords = localMatcher.evaluate(transcript: transcript, expectedWords: expectedWords)
        let expectedText = expectedWords.map(\.originalText)

        do {
            let observations = try await acousticAnalyzer.analyzeSpeech(transcript: transcript, expectedWords: expectedText)
            guard !observations.isEmpty else {
                return RecitationAnalysisResult(words: alignedWords, engine: .localMatcher)
            }

            let violations = rulesEngine.violations(expectedWords: expectedText, observations: observations)
            for violation in violations {
                guard alignedWords.indices.contains(violation.wordIndex) else { continue }
                alignedWords[violation.wordIndex].tajweedViolations.append(violation)
                if violation.severity == .critical {
                    alignedWords[violation.wordIndex].status = .missed
                } else if alignedWords[violation.wordIndex].status != .missed {
                    alignedWords[violation.wordIndex].status = .uncertain
                }
            }

            return RecitationAnalysisResult(words: alignedWords, engine: .coreML)
        } catch {
            return RecitationAnalysisResult(words: alignedWords, engine: .localMatcher)
        }
    }
}
