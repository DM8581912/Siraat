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
