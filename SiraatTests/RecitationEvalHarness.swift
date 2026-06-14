import Foundation
@testable import Siraat

// MARK: - Recitation / Tajweed evaluation harness (Milestone 0: the scoreboard)
//
// This is the objective measuring stick for "better than Tarteel". It runs the recitation
// and tajweed engines against a labeled fixture set and reports a fixed-format scoreboard:
// follow-along completeness, mistake-detection precision/recall, and per-rule tajweed
// precision/recall — plus the one number we never let regress, the false-positive rate on
// a correct reciter.
//
// It is deterministic and model-free on purpose: it drives the engines with synthetic
// transcripts and synthetic forced-alignments (we always know the target), so it runs in CI
// in milliseconds with no 90 MB acoustic model and no bundled audio. Real-audio evaluation
// against the large public corpora (IqraEval / EveryAyah) lives offline in
// `Scripts/eval_harness.py`; this Swift tier is the merge gate for honesty regressions.
//
// The fixtures use exact Al-Fatiha words for the follow-along path and a small, clearly
// test-only synthetic phoneme blueprint for the tajweed path. No Quranic phonetic data is
// invented here; the synthetic blueprint is labeled `corpus: "test"` and is never presented
// as scripture.

// MARK: Metric primitives

/// Precision/recall accumulator for one detector class.
struct DetectorScore: Equatable {
    var truePositives = 0
    var falsePositives = 0
    var falseNegatives = 0

    /// No false alarms => perfect precision. This is the honest default: a detector that
    /// predicts nothing never wrongly accuses a correct reciter.
    var precision: Double {
        let denom = truePositives + falsePositives
        return denom == 0 ? 1.0 : Double(truePositives) / Double(denom)
    }

    /// Nothing to find => perfect (vacuous) recall.
    var recall: Double {
        let denom = truePositives + falseNegatives
        return denom == 0 ? 1.0 : Double(truePositives) / Double(denom)
    }

    mutating func record(predicted: Bool, actual: Bool) {
        switch (predicted, actual) {
        case (true, true): truePositives += 1
        case (true, false): falsePositives += 1
        case (false, true): falseNegatives += 1
        case (false, false): break
        }
    }
}

// MARK: - Follow-along (word-level) evaluation

/// One labeled follow-along scenario: an expected ayah, a simulated recognizer transcript,
/// and the ground truth of what the reciter actually did.
struct WordFollowFixture {
    let name: String
    /// Expected words in Uthmani (exact Quranic text; never altered).
    let expected: [String]
    /// Diacritics-free transcript a recognizer would emit for this scenario.
    let transcript: String
    /// Truth: was each expected word actually recited correctly by this reciter?
    let idealCorrect: [Bool]
    /// Truth: expected indices the reciter omitted entirely.
    let skipped: Set<Int>
    /// Truth: expected indices the reciter said as a different word.
    let substituted: Set<Int>
}

struct WordFollowMetrics {
    /// Recall of the green "correct" verdict over words the reciter truly recited correctly.
    /// 1.0 = every correctly recited word was confirmed; low = the engine fails to keep up
    /// (the index matcher collapses here on isti'adha/basmala insertions and repeats).
    var followCompleteness: Double = 0
    /// Fraction of truly-correct words the engine marked with a hard error verdict (.missed).
    /// THE honesty number: must stay 0. A correct reciter is never told they erred.
    var hardFalsePositiveRate: Double = 0
    /// Detecting a real mistake (skip or substitution) by emitting a hard verdict (.missed).
    var mistake = DetectorScore()
    var perFixtureCompleteness: [(name: String, value: Double)] = []
}

enum RecitationFollowEval {
    static let fixtures: [WordFollowFixture] = {
        // Al-Fatiha 1:1, exact Uthmani words from FullQuran.json / TajweedBlueprints.json.
        let bism = "بِسْمِ"
        let allah = "ٱللَّهِ"
        let rahman = "ٱلرَّحْمَٰنِ"
        let rahim = "ٱلرَّحِيمِ"
        let verse = [bism, allah, rahman, rahim]
        // Diacritics-free forms a recognizer emits (matches ArabicTextNormalizer output).
        let n = (b: "بسم", a: "الله", rm: "الرحمن", ri: "الرحيم")

        return [
            // A correct, in-order recitation. The baseline handles this fine.
            WordFollowFixture(
                name: "perfect",
                expected: verse,
                transcript: "\(n.b) \(n.a) \(n.rm) \(n.ri)",
                idealCorrect: [true, true, true, true],
                skipped: [], substituted: []
            ),
            // Correct recitation preceded by isti'adha (a'udhu billah...). Every word is right,
            // but the leading tokens shift the index matcher so it confirms nothing.
            WordFollowFixture(
                name: "istiadha_prefix",
                expected: verse,
                transcript: "اعوذ بالله \(n.b) \(n.a) \(n.rm) \(n.ri)",
                idealCorrect: [true, true, true, true],
                skipped: [], substituted: []
            ),
            // Correct recitation where the reciter repeats a word (a natural stumble-and-continue).
            WordFollowFixture(
                name: "repeat_word",
                expected: verse,
                transcript: "\(n.b) \(n.a) \(n.a) \(n.rm) \(n.ri)",
                idealCorrect: [true, true, true, true],
                skipped: [], substituted: []
            ),
            // The reciter skips the third word entirely.
            WordFollowFixture(
                name: "skip_word",
                expected: verse,
                transcript: "\(n.b) \(n.a) \(n.ri)",
                idealCorrect: [true, true, false, true],
                skipped: [2], substituted: []
            ),
            // The reciter says a wrong word in the third position.
            WordFollowFixture(
                name: "substitute_word",
                expected: verse,
                transcript: "\(n.b) \(n.a) العظيم \(n.ri)",
                idealCorrect: [true, true, false, true],
                skipped: [], substituted: [2]
            )
        ]
    }()

    static func run(
        service: RecitationCorrectionServicing = RecitationCorrectionService(),
        fixtures: [WordFollowFixture] = RecitationFollowEval.fixtures
    ) -> WordFollowMetrics {
        var metrics = WordFollowMetrics()
        var completenessNum = 0, completenessDen = 0
        var hardFPNum = 0, hardFPDen = 0

        for fixture in fixtures {
            let expectedWords = fixture.expected.map { RecitationWord(originalText: $0) }
            let evaluated = service.evaluate(transcript: fixture.transcript, expectedWords: expectedWords)

            var fixtureNum = 0, fixtureDen = 0
            for index in fixture.expected.indices {
                let status = index < evaluated.count ? evaluated[index].status : .pending
                let predictedCorrect = status == .correct
                let predictedHardError = status == .missed
                let actualMistake = fixture.skipped.contains(index) || fixture.substituted.contains(index)

                if fixture.idealCorrect[index] {
                    completenessDen += 1; fixtureDen += 1
                    if predictedCorrect { completenessNum += 1; fixtureNum += 1 }
                    hardFPDen += 1
                    if predictedHardError { hardFPNum += 1 }
                }
                metrics.mistake.record(predicted: predictedHardError, actual: actualMistake)
            }
            metrics.perFixtureCompleteness.append(
                (fixture.name, fixtureDen == 0 ? 1 : Double(fixtureNum) / Double(fixtureDen))
            )
        }

        metrics.followCompleteness = completenessDen == 0 ? 1 : Double(completenessNum) / Double(completenessDen)
        metrics.hardFalsePositiveRate = hardFPDen == 0 ? 0 : Double(hardFPNum) / Double(hardFPDen)
        return metrics
    }

    /// The same fixtures run through the streaming forced-alignment engine (Milestone 1). The
    /// aligner has no hard-error state, so it cannot hard-flag a correct reciter; the win is
    /// follow-completeness, which the index matcher loses on isti'adha / repeats / skips.
    static func runStreaming(
        aligner: StreamingRecitationAligner = StreamingRecitationAligner(),
        fixtures: [WordFollowFixture] = RecitationFollowEval.fixtures
    ) -> WordFollowMetrics {
        var metrics = WordFollowMetrics()
        var completenessNum = 0, completenessDen = 0

        for fixture in fixtures {
            let words = aligner.align(expected: fixture.expected, transcript: fixture.transcript)
            var fixtureNum = 0, fixtureDen = 0
            for index in fixture.expected.indices {
                let state = index < words.count ? words[index].state : .pending
                let predictedCorrect = state == .correct
                let actualMistake = fixture.skipped.contains(index) || fixture.substituted.contains(index)
                if fixture.idealCorrect[index] {
                    completenessDen += 1; fixtureDen += 1
                    if predictedCorrect { completenessNum += 1; fixtureNum += 1 }
                }
                // No hard verdict here, so the mistake detector predicts nothing (recall stays
                // a Milestone 3 concern); honesty is structural.
                metrics.mistake.record(predicted: false, actual: actualMistake)
            }
            metrics.perFixtureCompleteness.append(
                (fixture.name, fixtureDen == 0 ? 1 : Double(fixtureNum) / Double(fixtureDen))
            )
        }

        metrics.followCompleteness = completenessDen == 0 ? 1 : Double(completenessNum) / Double(completenessDen)
        metrics.hardFalsePositiveRate = 0
        return metrics
    }
}

// MARK: - Tajweed (character-level) evaluation

struct TajweedScenario {
    let name: String
    let alignment: ForcedAlignment
    /// Truth: cluster index -> the error type that should be flagged. Absent => should be green.
    let expectedErrors: [Int: RecitationCharacterErrorType]
}

struct TajweedMetrics {
    /// Fraction of clusters flagged (non-green) where truth says green. Must stay 0.
    var falsePositiveRate: Double = 0
    var perRule: [(rule: String, score: DetectorScore)] = []
}

enum RecitationTajweedEval {
    /// A small, clearly test-only synthetic blueprint: a consonant, a Madd vowel, and a nasal
    /// that requires Ghunnah. Verified flag is true only so the evaluator runs; this is NOT
    /// presented as scripture (corpus = "test").
    static let uthmani = "بَامّ" // clusters: ب(+fatha), ا, م(+shadda)
    static func blueprint() -> AyahPhonemeMap {
        AyahPhonemeMap(
            verseKey: "test:1",
            scriptUthmani: uthmani,
            source: BlueprintProvenance(corpus: "test", attribution: "synthetic eval fixture", verified: true),
            phonemes: [
                CanonicalPhoneme(symbol: "b", baseLetter: "ب", isMaddVowel: false, expectedMaddCount: 0, expectedDurationSeconds: 0.18),
                CanonicalPhoneme(symbol: "A", baseLetter: "ا", isMaddVowel: true, expectedMaddCount: 2, expectedDurationSeconds: 0.9),
                CanonicalPhoneme(symbol: "m", baseLetter: "م", isMaddVowel: false, expectedMaddCount: 0, expectedDurationSeconds: 0.45, requiresGhunnah: true)
            ]
        )
    }

    private static func phoneme(_ base: Character, _ start: Double, _ end: Double, _ confidence: Double) -> AlignedPhoneme {
        AlignedPhoneme(symbol: String(base), baseLetter: base, start: start, end: end, confidence: confidence)
    }

    static func scenarios() -> [TajweedScenario] {
        [
            TajweedScenario(
                name: "clean",
                alignment: ForcedAlignment(phonemes: [
                    phoneme("ب", 0, 0.18, 0.9), phoneme("ا", 0.18, 1.08, 0.9), phoneme("م", 1.08, 1.58, 0.9)
                ], harakatSeconds: nil),
                expectedErrors: [:]
            ),
            TajweedScenario(
                name: "short_madd",
                alignment: ForcedAlignment(phonemes: [
                    phoneme("ب", 0, 0.18, 0.9), phoneme("ا", 0.18, 0.48, 0.9), phoneme("م", 0.48, 0.98, 0.9)
                ], harakatSeconds: nil),
                expectedErrors: [1: .maddShort]
            ),
            TajweedScenario(
                name: "missed_ghunnah",
                alignment: ForcedAlignment(phonemes: [
                    phoneme("ب", 0, 0.18, 0.9), phoneme("ا", 0.18, 1.08, 0.9), phoneme("م", 1.08, 1.18, 0.9)
                ], harakatSeconds: nil),
                expectedErrors: [2: .ghunnahMissed]
            ),
            TajweedScenario(
                name: "wrong_letter",
                alignment: ForcedAlignment(phonemes: [
                    phoneme("ت", 0, 0.18, 0.95), phoneme("ا", 0.18, 1.08, 0.9), phoneme("م", 1.08, 1.58, 0.9)
                ], harakatSeconds: nil),
                expectedErrors: [0: .tashkeelWrong]
            ),
            // Honesty: the model is unsure (low confidence). We must NOT flag, even though it
            // "heard" a different letter.
            TajweedScenario(
                name: "low_confidence_unsure",
                alignment: ForcedAlignment(phonemes: [
                    phoneme("ت", 0, 0.18, 0.45), phoneme("ا", 0.18, 0.30, 0.45), phoneme("م", 0.30, 0.34, 0.45)
                ], harakatSeconds: nil),
                expectedErrors: [:]
            ),
            // Honesty under degradation: no acoustic model bundled => placeholder alignment =>
            // nothing is ever flagged.
            TajweedScenario(
                name: "model_absent_placeholder",
                alignment: CoreMLForcedAligner.placeholderAlignment(for: blueprint()),
                expectedErrors: [:]
            )
        ]
    }

    static let ruleTypes: [RecitationCharacterErrorType] = [.maddShort, .maddLong, .ghunnahMissed, .tashkeelWrong, .missed]

    static func run(
        evaluator: CharacterTajweedEvaluator = CharacterTajweedEvaluator(),
        scenarios: [TajweedScenario] = RecitationTajweedEval.scenarios()
    ) -> TajweedMetrics {
        var perRule: [RecitationCharacterErrorType: DetectorScore] = [:]
        var fpNum = 0, fpDen = 0
        let map = blueprint()

        for scenario in scenarios {
            let results = evaluator.evaluate(uthmani: uthmani, blueprint: map, alignment: scenario.alignment)
            for (index, result) in results.enumerated() {
                let truthError = scenario.expectedErrors[index]
                fpDen += 1
                if result.color != .green && truthError == nil { fpNum += 1 }
                for rule in ruleTypes {
                    perRule[rule, default: DetectorScore()].record(
                        predicted: result.errorType == rule,
                        actual: truthError == rule
                    )
                }
            }
        }

        var metrics = TajweedMetrics()
        metrics.falsePositiveRate = fpDen == 0 ? 0 : Double(fpNum) / Double(fpDen)
        metrics.perRule = ruleTypes.map { ($0.rawValue, perRule[$0] ?? DetectorScore()) }
        return metrics
    }
}

// MARK: - Scoreboard rendering

enum RecitationScoreboard {
    static func render(word: WordFollowMetrics, tajweed: TajweedMetrics) -> String {
        func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
        func num(_ v: Double) -> String { String(format: "%.2f", v) }
        var lines: [String] = []
        lines.append("================ RECITATION EVAL SCOREBOARD ================")
        lines.append("FOLLOW-ALONG (word level)")
        lines.append("  follow-completeness (correct words confirmed): \(pct(word.followCompleteness))")
        lines.append("  HARD false-positive rate on correct reciter:   \(pct(word.hardFalsePositiveRate))  [honesty: must be 0%]")
        lines.append("  mistake precision: \(num(word.mistake.precision))  recall: \(num(word.mistake.recall))  (TP \(word.mistake.truePositives) FP \(word.mistake.falsePositives) FN \(word.mistake.falseNegatives))")
        for fixture in word.perFixtureCompleteness {
            lines.append("    - \(fixture.name): completeness \(pct(fixture.value))")
        }
        lines.append("TAJWEED (character level)")
        lines.append("  false-positive rate on green truth: \(pct(tajweed.falsePositiveRate))  [honesty: must be 0%]")
        for entry in tajweed.perRule where entry.score.truePositives + entry.score.falseNegatives + entry.score.falsePositives > 0 {
            lines.append("    - \(entry.rule): precision \(num(entry.score.precision)) recall \(num(entry.score.recall))")
        }
        lines.append("============================================================")
        return lines.joined(separator: "\n")
    }
}
