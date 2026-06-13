import Foundation

final class HybridRecitationAnalysisProvider: RecitationAnalysisProviding {
    private let localMatcher: RecitationCorrectionServicing
    private let acousticAnalyzer: TajweedAcousticAnalyzing
    private let rulesEngine: TajweedRulesEngine
    private let forcedAligner: PhoneticForcedAligning
    private let characterEvaluator: CharacterTajweedEvaluator

    init(
        localMatcher: RecitationCorrectionServicing = RecitationCorrectionService(),
        acousticAnalyzer: TajweedAcousticAnalyzing = CoreMLTajweedAcousticAnalyzer(),
        rulesEngine: TajweedRulesEngine = TajweedRulesEngine(),
        forcedAligner: PhoneticForcedAligning = CoreMLForcedAligner(),
        characterEvaluator: CharacterTajweedEvaluator = CharacterTajweedEvaluator()
    ) {
        self.localMatcher = localMatcher
        self.acousticAnalyzer = acousticAnalyzer
        self.rulesEngine = rulesEngine
        self.forcedAligner = forcedAligner
        self.characterEvaluator = characterEvaluator
    }

    func analyzeCharacters(
        uthmani: String,
        blueprint: AyahPhonemeMap,
        samples: [Float],
        sampleRate: Double
    ) async -> [RecitationCharacterResult] {
        do {
            let aligned = try await forcedAligner.align(
                samples: samples,
                sampleRate: sampleRate,
                against: blueprint
            )
            return characterEvaluator.evaluate(uthmani: uthmani, blueprint: blueprint, aligned: aligned)
        } catch {
            return []
        }
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
