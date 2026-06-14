import XCTest
@testable import Siraat

/// Milestone 3: honest mistake detection. These tests prove the precision-first contract — a
/// correct reciter is never accused of a mistake even under noisy conditions (isti'adha
/// prefix, stutter repeats, recognizer slips), and real skips / substitutions are surfaced.
final class RecitationMistakeDetectorTests: XCTestCase {
    // Al-Fatiha 1:1, exact Uthmani words.
    private let verse = ["بِسْمِ", "ٱللَّهِ", "ٱلرَّحْمَٰنِ", "ٱلرَّحِيمِ"]
    private let detector = RecitationMistakeDetector()

    // MARK: Honesty — a correct reciter is never accused.

    func testPerfectRecitationProducesNoFindings() {
        let findings = detector.detect(expected: verse, transcript: "بسم الله الرحمن الرحيم")
        XCTAssertTrue(findings.isEmpty, "Hard-flagged a correct reciter: \(findings)")
    }

    func testIstiadhaPrefixIsNeverFlaggedAsAdded() {
        // The user said a'udhu billah before reciting — a sunnah, not a mistake.
        let findings = detector.detect(
            expected: verse,
            transcript: "اعوذ بالله بسم الله الرحمن الرحيم"
        )
        XCTAssertTrue(findings.isEmpty, "isti'adha was misclassified as added: \(findings)")
    }

    func testStutterRepeatIsNotAnAddedMistake() {
        // The reciter repeats الله in the second slot, then continues correctly. This is a
        // recitation stutter (very common in live recitation), not an added word.
        let findings = detector.detect(
            expected: verse,
            transcript: "بسم الله الله الرحمن الرحيم"
        )
        XCTAssertTrue(findings.isEmpty, "Stutter repeat was flagged: \(findings)")
    }

    func testMidRecitationDoesNotFlagUnreachedWords() {
        // The reciter has only said the first two words so far. We must not pre-emptively
        // accuse them of skipping the rest — the alignment head has not moved past.
        let findings = detector.detect(expected: verse, transcript: "بسم الله")
        XCTAssertTrue(findings.isEmpty, "Pre-emptively flagged unreached words: \(findings)")
    }

    // MARK: Real mistakes — surfaced precisely.

    func testSkippedWordIsConfidentlyFlagged() {
        let findings = detector.detect(
            expected: verse,
            transcript: "بسم الله الرحيم"
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.kind, .skipped)
        XCTAssertEqual(findings.first?.expectedWordIndex, 2) // الرحمن
        XCTAssertGreaterThanOrEqual(findings.first?.confidence ?? 0, 0.9)
    }

    func testSubstitutedWordIsConfidentlyFlagged() {
        // العظيم in place of الرحمن is a different word entirely (distance > 1) — a clear sub.
        let findings = detector.detect(
            expected: verse,
            transcript: "بسم الله العظيم الرحيم"
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.kind, .substituted)
        XCTAssertEqual(findings.first?.expectedWordIndex, 2)
        XCTAssertEqual(findings.first?.spokenToken, "العظيم")
    }

    func testTrulyAddedWordIsFlagged() {
        // A non-recitation-optional inserted word between the correct ones.
        let findings = detector.detect(
            expected: verse,
            transcript: "بسم الله ربي الرحمن الرحيم"
        )
        let added = findings.filter { $0.kind == .added }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.spokenToken, "ربي")
    }

    func testRecognizerSlipWithinOneEditIsNotFlagged() {
        // A one-edit recognizer slip on the last word — heard as "الرحم" instead of "الرحيم".
        // Fuzzy distance 1, so the streaming aligner follow-matches it; the mistake detector
        // must therefore not flag the slot as substituted.
        let findings = detector.detect(
            expected: verse,
            transcript: "بسم الله الرحمن الرحم"
        )
        XCTAssertTrue(
            findings.allSatisfy { $0.kind != .substituted },
            "Recognizer slip was accused of substitution: \(findings)"
        )
    }
}

final class StreamingMistakeConfirmerTests: XCTestCase {
    func testTransientFindingNeverFiresIfItDisappears() {
        // The detector emits a finding at tick 1; at tick 2 it has gone (the next word
        // arrived and the alignment refined). The confirmer must never have released it.
        let confirmer = StreamingMistakeConfirmer()
        let f = MistakeFinding(kind: .skipped, expectedWordIndex: 2, spokenTokenIndex: nil, spokenToken: nil, confidence: 0.95)
        XCTAssertTrue(confirmer.ingest([f]).isEmpty) // tick 1: pending only
        XCTAssertTrue(confirmer.ingest([]).isEmpty)  // tick 2: gone — released
        XCTAssertTrue(confirmer.ingest([f]).isEmpty) // tick 3: starts over as pending
    }

    func testStableFindingFiresOnSecondTick() {
        let confirmer = StreamingMistakeConfirmer()
        let f = MistakeFinding(kind: .skipped, expectedWordIndex: 2, spokenTokenIndex: nil, spokenToken: nil, confidence: 0.95)
        XCTAssertTrue(confirmer.ingest([f]).isEmpty)        // tick 1: pending
        XCTAssertEqual(confirmer.ingest([f]).count, 1)      // tick 2: confirmed → fires
        XCTAssertEqual(confirmer.ingest([f]).count, 1)      // tick 3: stays confirmed
    }

    func testConfirmedFindingStaysOutEvenIfBrieflyAbsent() {
        // Once a hard verdict has been confirmed, a stray miss on one tick must not undo it
        // (we don't unsay a hard verdict mid-session). Reset is for between sessions.
        let confirmer = StreamingMistakeConfirmer()
        let f = MistakeFinding(kind: .substituted, expectedWordIndex: 2, spokenTokenIndex: 2, spokenToken: "العظيم", confidence: 0.9)
        _ = confirmer.ingest([f])
        XCTAssertEqual(confirmer.ingest([f]).count, 1) // confirmed
        _ = confirmer.ingest([])                       // brief absence
        XCTAssertEqual(confirmer.ingest([f]).count, 1) // still released
    }

    func testResetClearsState() {
        let confirmer = StreamingMistakeConfirmer()
        let f = MistakeFinding(kind: .skipped, expectedWordIndex: 2, spokenTokenIndex: nil, spokenToken: nil, confidence: 0.95)
        _ = confirmer.ingest([f])
        _ = confirmer.ingest([f])
        confirmer.reset()
        XCTAssertTrue(confirmer.ingest([f]).isEmpty) // pending again post-reset
    }
}
