import XCTest
@testable import Siraat

/// Milestone 1: the streaming forced-alignment engine. These tests prove it does what index
/// matching cannot — keep following a correct reciter through isti'adha, repeats, and skips —
/// while never hard-flagging a correct reciter, and they show the follow-completeness delta on
/// the eval harness fixtures.
final class StreamingRecitationAlignerTests: XCTestCase {
    // Al-Fatiha 1:1, exact Uthmani words.
    private let verse = ["بِسْمِ", "ٱللَّهِ", "ٱلرَّحْمَٰنِ", "ٱلرَّحِيمِ"]
    private let aligner = StreamingRecitationAligner()

    func testPerfectRecitationAllCorrect() {
        let words = aligner.align(expected: verse, transcript: "بسم الله الرحمن الرحيم")
        XCTAssertEqual(words.map(\.state), [.correct, .correct, .correct, .correct])
        XCTAssertEqual(words.map(\.matchedTokenIndex), [0, 1, 2, 3] as [Int?])
    }

    func testIstiadhaPrefixStillTracksEntireVerse() {
        // The reciter says a'udhu billah first; the index matcher then confirms nothing.
        let words = aligner.align(expected: verse, transcript: "اعوذ بالله بسم الله الرحمن الرحيم")
        XCTAssertEqual(words.map(\.state), [.correct, .correct, .correct, .correct])
        // The matched tokens skip past the two isti'adha tokens.
        XCTAssertEqual(words.map(\.matchedTokenIndex), [2, 3, 4, 5] as [Int?])
    }

    func testRepeatedWordStillTracks() {
        let words = aligner.align(expected: verse, transcript: "بسم الله الله الرحمن الرحيم")
        XCTAssertEqual(words.map(\.state), [.correct, .correct, .correct, .correct])
    }

    func testSkippedMiddleWordIsUncertainAndTailRecovers() {
        let words = aligner.align(expected: verse, transcript: "بسم الله الرحيم")
        XCTAssertEqual(words[0].state, .correct)
        XCTAssertEqual(words[1].state, .correct)
        XCTAssertEqual(words[2].state, .uncertain)   // skipped — reached but unmatched, never accused
        XCTAssertNil(words[2].matchedTokenIndex)
        XCTAssertEqual(words[3].state, .correct)      // tail re-acquired after the skip
    }

    func testSubstitutedWordIsUncertainOthersCorrect() {
        let words = aligner.align(expected: verse, transcript: "بسم الله العظيم الرحيم")
        XCTAssertEqual(words.map(\.state), [.correct, .correct, .uncertain, .correct])
        XCTAssertEqual(words[2].matchedTokenIndex, 2) // it knows where the wrong word sits (for the marker)
    }

    func testNeverHardFlagsACorrectReciter() {
        // Honesty: a correct reciter only ever sees .correct, regardless of isti'adha/repeat.
        for transcript in [
            "بسم الله الرحمن الرحيم",
            "اعوذ بالله بسم الله الرحمن الرحيم",
            "بسم الله الله الرحمن الرحيم"
        ] {
            let words = aligner.align(expected: verse, transcript: transcript)
            XCTAssertTrue(words.allSatisfy { $0.state == .correct }, "transcript: \(transcript)")
        }
    }

    func testEmptyTranscriptIsPendingWithActiveHead() {
        let words = aligner.align(expected: verse, transcript: "")
        XCTAssertEqual(words[0].state, .active)
        XCTAssertEqual(words.dropFirst().map(\.state), [.pending, .pending, .pending])
    }

    func testFuzzyMatchToleratesOneEditSlip() {
        // One-edit recognizer slip still follows (lower confidence, still a follow match).
        let words = aligner.align(expected: ["ٱلرَّحِيمِ"], transcript: "الرحم")
        XCTAssertEqual(words[0].state, .correct)
        XCTAssertEqual(words[0].confidence, 0.75, accuracy: 0.001)
    }

    // MARK: The headline metric delta

    func testStreamingAlignerBeatsBaselineFollowCompleteness() {
        let baseline = RecitationFollowEval.run()            // current index matcher
        let streaming = RecitationFollowEval.runStreaming()  // the new aligner
        print("FOLLOW-COMPLETENESS  baseline=\(String(format: "%.2f", baseline.followCompleteness))  streaming=\(String(format: "%.2f", streaming.followCompleteness))")
        for fixture in streaming.perFixtureCompleteness {
            let base = baseline.perFixtureCompleteness.first { $0.name == fixture.name }?.value ?? 0
            print("  \(fixture.name): \(String(format: "%.2f", base)) -> \(String(format: "%.2f", fixture.value))")
        }
        // Honesty preserved, and a large, real jump on the same labeled fixtures.
        XCTAssertEqual(streaming.hardFalsePositiveRate, 0, "Streaming aligner hard-flagged a correct reciter.")
        XCTAssertGreaterThanOrEqual(streaming.followCompleteness, 0.95)
        XCTAssertGreaterThan(streaming.followCompleteness, baseline.followCompleteness + 0.3)
    }
}
