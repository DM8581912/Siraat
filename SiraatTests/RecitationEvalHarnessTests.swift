import XCTest
@testable import Siraat

/// Milestone 0: the evaluation harness is the scoreboard every later milestone moves.
///
/// These tests assert the invariants we never let regress (honesty: a correct reciter is
/// never told they erred) and pin the current baseline so future PRs report a real delta.
/// The printed scoreboard is captured in CI logs.
final class RecitationEvalHarnessTests: XCTestCase {
    func testPrintsScoreboard() {
        let word = RecitationFollowEval.run()
        let tajweed = RecitationTajweedEval.run()
        print(RecitationScoreboard.render(word: word, tajweed: tajweed))
    }

    func testPrintsMilestoneDeltaScoreboard() {
        let baseline = RecitationFollowEval.run()
        let streaming = RecitationFollowEval.runStreaming()
        let withMistakes = RecitationFollowEval.runStreamingWithMistakes()
        print("================ FOLLOW-ALONG MILESTONE DELTAS ================")
        print(String(format: "  follow-completeness  M0=%.2f  M1/M2=%.2f  M3=%.2f",
                     baseline.followCompleteness, streaming.followCompleteness, withMistakes.followCompleteness))
        print(String(format: "  hard FP rate (honesty must stay 0%%)  M0=%.0f%%  M1/M2=%.0f%%  M3=%.0f%%",
                     baseline.hardFalsePositiveRate * 100, streaming.hardFalsePositiveRate * 100, withMistakes.hardFalsePositiveRate * 100))
        print(String(format: "  mistake precision/recall  M0=%.2f/%.2f  M3=%.2f/%.2f",
                     baseline.mistake.precision, baseline.mistake.recall,
                     withMistakes.mistake.precision, withMistakes.mistake.recall))
        print("===============================================================")
    }

    // MARK: M3 — honest mistake detection must lift recall without breaking honesty

    func testMistakeDetectionLiftsRecallAtFullPrecisionAndZeroFalsePositives() {
        let m3 = RecitationFollowEval.runStreamingWithMistakes()
        // Honesty: not a single correct word may be hard-flagged across any fixture.
        XCTAssertEqual(m3.hardFalsePositiveRate, 0, "M3 hard-flagged a correct reciter — honesty regression.")
        XCTAssertEqual(m3.mistake.falsePositives, 0, "M3 raised a false mistake — honesty regression.")
        // Precision target: 1.0 on the fixtures (zero false positives by construction).
        XCTAssertEqual(m3.mistake.precision, 1.0, accuracy: 0.0001)
        // Recall target: every seeded mistake (skip + substitution) caught.
        XCTAssertEqual(m3.mistake.recall, 1.0, accuracy: 0.0001,
                       "Missed a seeded mistake — recall regression.")
        // Follow-completeness must not collapse just because mistakes are now being surfaced.
        XCTAssertGreaterThanOrEqual(m3.followCompleteness, 0.95)
    }

    // MARK: Honesty invariants (hard — must always hold)

    func testFollowAlongNeverHardFlagsACorrectReciter() {
        // No correctly recited word may ever receive a hard error verdict, including when the
        // reciter prepends isti'adha or repeats a word. The engine may fail to confirm a word
        // (low completeness), but it must never accuse.
        let word = RecitationFollowEval.run()
        XCTAssertEqual(word.hardFalsePositiveRate, 0, "A correct reciter was hard-flagged — honesty regression.")
        XCTAssertEqual(word.mistake.falsePositives, 0, "A correct word was reported as a mistake — honesty regression.")
    }

    func testTajweedNeverFlagsWhenUnsureOrModelAbsent() {
        // Low-confidence guesses and the model-absent placeholder path must produce zero flags.
        let tajweed = RecitationTajweedEval.run()
        XCTAssertEqual(tajweed.falsePositiveRate, 0, "Tajweed flagged a green-truth cluster — honesty regression.")
    }

    func testTajweedPlaceholderAlignmentIsAllGreen() {
        let map = RecitationTajweedEval.blueprint()
        let results = CharacterTajweedEvaluator().evaluate(
            uthmani: RecitationTajweedEval.uthmani,
            blueprint: map,
            alignment: CoreMLForcedAligner.placeholderAlignment(for: map)
        )
        XCTAssertEqual(results.map(\.color), Array(repeating: RecitationCharacterColor.green, count: results.count))
        XCTAssertTrue(results.allSatisfy { $0.errorType == nil })
    }

    // MARK: Baseline (documents the "before" the streaming engine will beat)

    func testBaselineMatcherDetectsNoMistakes() {
        // The current index matcher deliberately never says "wrong": perfect precision, zero
        // recall. Milestone 3 (honest mistake detection) is what moves recall off the floor.
        let word = RecitationFollowEval.run()
        XCTAssertEqual(word.mistake.recall, 0, accuracy: 0.0001,
                       "Baseline mistake recall changed; update eval/baseline.json with the new number.")
        XCTAssertEqual(word.mistake.precision, 1.0, accuracy: 0.0001)
    }

    func testBaselineIndexMatcherCollapsesOnIstiadhaPrefix() {
        // The compelling gap: a fully-correct recitation that begins with isti'adha confirms
        // (almost) nothing under index matching. Milestone 2 (streaming alignment) closes this.
        let word = RecitationFollowEval.run()
        let istiadha = word.perFixtureCompleteness.first { $0.name == "istiadha_prefix" }?.value
        XCTAssertNotNil(istiadha)
        XCTAssertLessThan(istiadha ?? 1, 0.5,
                          "Index matcher unexpectedly tracked the isti'adha prefix — re-baseline.")
    }

    // MARK: Tajweed detector logic is sound on the rules it covers

    func testTajweedCoveredRulesAreHighPrecisionAndRecall() {
        // Where the evaluator does grade (Madd length, Ghunnah duration, confident wrong
        // letter), it is precise and complete on the seeded errors. The gap is COVERAGE
        // (qalqalah/idgham/ikhfa absent, corpus unverified, consonants ungraded), not logic.
        let tajweed = RecitationTajweedEval.run()
        for rule in ["madd_short", "ghunnah_missed", "tashkeel_wrong"] {
            let score = tajweed.perRule.first { $0.rule == rule }?.score
            XCTAssertNotNil(score, "Missing rule \(rule) in scoreboard.")
            XCTAssertEqual(score?.precision ?? 0, 1.0, accuracy: 0.0001, "\(rule) precision regressed.")
            XCTAssertEqual(score?.recall ?? 0, 1.0, accuracy: 0.0001, "\(rule) recall regressed.")
        }
    }
}
