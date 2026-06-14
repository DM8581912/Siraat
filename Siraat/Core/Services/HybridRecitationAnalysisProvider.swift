import Foundation

final class HybridRecitationAnalysisProvider: RecitationAnalysisProviding {
    /// Opt-in flag for the streaming forced-alignment follow-along. Default off → the existing
    /// index matcher. Read on each analysis so the Settings toggle takes effect immediately.
    static let streamingFollowDefaultsKey = "streamingFollowAlongEnabled"

    private let localMatcher: RecitationCorrectionServicing
    private let streamingAligner: StreamingRecitationAligner
    private let useStreamingFollow: () -> Bool
    private let acousticAnalyzer: TajweedAcousticAnalyzing
    private let rulesEngine: TajweedRulesEngine
    private let forcedAligner: PhoneticForcedAligning
    private let characterEvaluator: CharacterTajweedEvaluator

    init(
        localMatcher: RecitationCorrectionServicing = RecitationCorrectionService(),
        streamingAligner: StreamingRecitationAligner = StreamingRecitationAligner(),
        useStreamingFollow: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: HybridRecitationAnalysisProvider.streamingFollowDefaultsKey)
        },
        acousticAnalyzer: TajweedAcousticAnalyzing = CoreMLTajweedAcousticAnalyzer(),
        rulesEngine: TajweedRulesEngine = TajweedRulesEngine(),
        forcedAligner: PhoneticForcedAligning = CoreMLForcedAligner(),
        characterEvaluator: CharacterTajweedEvaluator = CharacterTajweedEvaluator()
    ) {
        self.localMatcher = localMatcher
        self.streamingAligner = streamingAligner
        self.useStreamingFollow = useStreamingFollow
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
            let alignment = try await forcedAligner.align(
                samples: samples,
                sampleRate: sampleRate,
                against: blueprint
            )
            return characterEvaluator.evaluate(uthmani: uthmani, blueprint: blueprint, alignment: alignment)
        } catch {
            return []
        }
    }

    func analyze(transcript: String, expectedWords: [RecitationWord]) async -> RecitationAnalysisResult {
        let usingStreaming = useStreamingFollow()
        var alignedWords = usingStreaming
            ? streamingFollow(transcript: transcript, expectedWords: expectedWords)
            : localMatcher.evaluate(transcript: transcript, expectedWords: expectedWords)
        let baseEngine: RecitationAnalysisEngine = usingStreaming ? .streamingAlign : .localMatcher
        let expectedText = expectedWords.map(\.originalText)

        do {
            let observations = try await acousticAnalyzer.analyzeSpeech(transcript: transcript, expectedWords: expectedText)
            guard !observations.isEmpty else {
                return RecitationAnalysisResult(words: alignedWords, engine: baseEngine)
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
            return RecitationAnalysisResult(words: alignedWords, engine: baseEngine)
        }
    }

    /// Map the streaming aligner's per-word follow states onto the word-status model. Honest by
    /// construction: nothing here is a hard error — an unmatched word stays `uncertain`, never
    /// `.missed`. Hard mistake verdicts are a separate, higher-precision stage.
    private func streamingFollow(transcript: String, expectedWords: [RecitationWord]) -> [RecitationWord] {
        let follow = streamingAligner.align(expected: expectedWords.map(\.originalText), transcript: transcript)
        return expectedWords.enumerated().map { index, word in
            var updated = word
            updated.tajweedViolations = []
            updated.tip = nil
            switch index < follow.count ? follow[index].state : .pending {
            case .correct: updated.status = .correct
            case .uncertain: updated.status = .uncertain
            case .active, .pending: updated.status = .pending
            }
            return updated
        }
    }
}
