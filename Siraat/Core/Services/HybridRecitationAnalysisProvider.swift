import Foundation

final class HybridRecitationAnalysisProvider: RecitationAnalysisProviding {
    /// Opt-in flag for the streaming forced-alignment follow-along. Default off → the existing
    /// index matcher. Read on each analysis so the Settings toggle takes effect immediately.
    static let streamingFollowDefaultsKey = "streamingFollowAlongEnabled"

    /// Opt-in flag for honest, precision-first mistake detection. Requires streaming follow to
    /// also be on (the detector consumes the aligner's per-word trace). Default off — this is
    /// the only path that can produce a hard verdict for a word, and a session is reset
    /// between verses so a confirmed verdict doesn't leak across.
    static let mistakeDetectionDefaultsKey = "mistakeDetectionEnabled"

    private let localMatcher: RecitationCorrectionServicing
    private let streamingAligner: StreamingRecitationAligner
    private let useStreamingFollow: () -> Bool
    private let mistakeDetector: RecitationMistakeDetector
    private let mistakeConfirmer: StreamingMistakeConfirmer
    private let useMistakeDetection: () -> Bool
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
        mistakeDetector: RecitationMistakeDetector = RecitationMistakeDetector(),
        mistakeConfirmer: StreamingMistakeConfirmer = StreamingMistakeConfirmer(),
        useMistakeDetection: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: HybridRecitationAnalysisProvider.mistakeDetectionDefaultsKey)
        },
        acousticAnalyzer: TajweedAcousticAnalyzing = CoreMLTajweedAcousticAnalyzer(),
        rulesEngine: TajweedRulesEngine = TajweedRulesEngine(),
        forcedAligner: PhoneticForcedAligning = CoreMLForcedAligner(),
        characterEvaluator: CharacterTajweedEvaluator = CharacterTajweedEvaluator()
    ) {
        self.localMatcher = localMatcher
        self.streamingAligner = streamingAligner
        self.useStreamingFollow = useStreamingFollow
        self.mistakeDetector = mistakeDetector
        self.mistakeConfirmer = mistakeConfirmer
        self.useMistakeDetection = useMistakeDetection
        self.acousticAnalyzer = acousticAnalyzer
        self.rulesEngine = rulesEngine
        self.forcedAligner = forcedAligner
        self.characterEvaluator = characterEvaluator
    }

    /// Clears the streaming mistake confirmer between verses / sessions so a confirmed verdict
    /// from a previous ayah doesn't leak into the next. Call when the user picks a new verse
    /// or taps Reset.
    func resetSession() {
        mistakeConfirmer.reset()
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
        let expectedText = expectedWords.map(\.originalText)
        var alignedWords: [RecitationWord]
        var activeWordIndex: Int?
        if usingStreaming {
            let follow = streamingAligner.align(expected: expectedText, transcript: transcript)
            alignedWords = mapFollowToWords(follow: follow, expectedWords: expectedWords)
            activeWordIndex = follow.firstIndex { $0.state == .active }
            // Honest mistake detection runs on top of the same alignment trace, only when its
            // own flag is also on. Findings only escalate a slot from .uncertain to .missed
            // after the streaming confirmer has seen the same finding two ticks in a row.
            if useMistakeDetection() {
                let spoken = ArabicTextNormalizer.tokens(from: transcript)
                let raw = mistakeDetector.detect(expected: expectedText, spokenTokens: spoken, follow: follow)
                let confirmed = mistakeConfirmer.ingest(raw)
                for finding in confirmed {
                    guard let idx = finding.expectedWordIndex,
                          alignedWords.indices.contains(idx)
                    else { continue }
                    alignedWords[idx].status = .missed
                }
            }
        } else {
            alignedWords = localMatcher.evaluate(transcript: transcript, expectedWords: expectedWords)
        }
        let baseEngine: RecitationAnalysisEngine = usingStreaming ? .streamingAlign : .localMatcher

        do {
            let observations = try await acousticAnalyzer.analyzeSpeech(transcript: transcript, expectedWords: expectedText)
            guard !observations.isEmpty else {
                return RecitationAnalysisResult(words: alignedWords, engine: baseEngine, activeWordIndex: activeWordIndex)
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

            return RecitationAnalysisResult(words: alignedWords, engine: .coreML, activeWordIndex: activeWordIndex)
        } catch {
            return RecitationAnalysisResult(words: alignedWords, engine: baseEngine, activeWordIndex: activeWordIndex)
        }
    }

    /// Map the streaming aligner's per-word follow states onto the word-status model. Honest by
    /// construction: nothing here is a hard error — an unmatched word stays `uncertain`, never
    /// `.missed`. Hard mistake verdicts are layered on top by the mistake detector.
    private func mapFollowToWords(follow: [FollowWord], expectedWords: [RecitationWord]) -> [RecitationWord] {
        expectedWords.enumerated().map { index, word in
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
