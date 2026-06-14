import XCTest
@testable import Siraat

final class RecitationAnalysisProviderTests: XCTestCase {
    func testHybridProviderFallsBackToLocalMatcherWhenCoreMLModelIsUnavailable() async {
        let provider = HybridRecitationAnalysisProvider()
        let words = [
            RecitationWord(originalText: "ٱلْحَمْدُ"),
            RecitationWord(originalText: "لِلَّهِ")
        ]

        let result = await provider.analyze(transcript: "الحمد لله", expectedWords: words)

        XCTAssertEqual(result.engine, .localMatcher)
        XCTAssertEqual(result.words.map(\.status), [.correct, .correct])
    }

    func testStreamingFollowTracksThroughIstiadhaPrefixWhenEnabled() async {
        // With the opt-in streaming follow on, a correct recitation preceded by isti'adha is
        // still fully confirmed — the index matcher confirms none of these words.
        let provider = HybridRecitationAnalysisProvider(useStreamingFollow: { true })
        let words = [
            RecitationWord(originalText: "بِسْمِ"),
            RecitationWord(originalText: "ٱللَّهِ"),
            RecitationWord(originalText: "ٱلرَّحْمَٰنِ"),
            RecitationWord(originalText: "ٱلرَّحِيمِ")
        ]

        let result = await provider.analyze(
            transcript: "اعوذ بالله بسم الله الرحمن الرحيم",
            expectedWords: words
        )

        XCTAssertEqual(result.engine, .streamingAlign)
        XCTAssertEqual(result.words.map(\.status), [.correct, .correct, .correct, .correct])
        // Honesty: never a hard verdict for a correct reciter.
        XCTAssertFalse(result.words.contains { $0.status == .missed })
    }

    func testStreamingFollowDefaultsOff() async {
        // Without the flag the provider keeps the existing index matcher.
        let provider = HybridRecitationAnalysisProvider()
        let words = [RecitationWord(originalText: "بِسْمِ"), RecitationWord(originalText: "ٱللَّهِ")]
        let result = await provider.analyze(transcript: "بسم الله", expectedWords: words)
        XCTAssertEqual(result.engine, .localMatcher)
    }

    // MARK: Milestone 3 — honest mistake detection through the provider

    func testMistakeDetectionEscalatesConfirmedSkipToMissed() async {
        // The confirmer requires two consecutive identical findings before releasing one as a
        // hard verdict. We feed the same transcript twice on one provider instance and verify
        // the second analysis escalates the skipped word's status to .missed.
        let provider = HybridRecitationAnalysisProvider(
            useStreamingFollow: { true },
            useMistakeDetection: { true }
        )
        let verse = [
            RecitationWord(originalText: "بِسْمِ"),
            RecitationWord(originalText: "ٱللَّهِ"),
            RecitationWord(originalText: "ٱلرَّحْمَٰنِ"),
            RecitationWord(originalText: "ٱلرَّحِيمِ")
        ]
        // Tick 1: the reciter has said three words but skipped ٱلرَّحْمَٰنِ — pending only.
        let tick1 = await provider.analyze(transcript: "بسم الله الرحيم", expectedWords: verse)
        XCTAssertNotEqual(tick1.words[2].status, .missed, "Mistake fired on tick 1 — confirmer skipped.")
        // Tick 2: same evidence persists — the confirmer releases the verdict.
        let tick2 = await provider.analyze(transcript: "بسم الله الرحيم", expectedWords: verse)
        XCTAssertEqual(tick2.words[2].status, .missed)
        XCTAssertEqual(tick2.engine, .streamingAlign)
        // Honesty: the surrounding correctly-recited words must not be hard-flagged.
        for index in [0, 1, 3] {
            XCTAssertNotEqual(tick2.words[index].status, .missed, "False positive on word \(index)")
        }
    }

    func testMistakeDetectionNeverFiresForACorrectReciterUnderRepeatedAnalysis() async {
        // The honesty contract: no matter how many ticks of a fully correct (even prefixed
        // with isti'adha and stuttered) transcript we feed, no word may ever turn .missed.
        let provider = HybridRecitationAnalysisProvider(
            useStreamingFollow: { true },
            useMistakeDetection: { true }
        )
        let verse = [
            RecitationWord(originalText: "بِسْمِ"),
            RecitationWord(originalText: "ٱللَّهِ"),
            RecitationWord(originalText: "ٱلرَّحْمَٰنِ"),
            RecitationWord(originalText: "ٱلرَّحِيمِ")
        ]
        let transcripts = [
            "بسم الله",
            "بسم الله الرحمن",
            "اعوذ بالله بسم الله الرحمن الرحيم",
            "بسم الله الله الرحمن الرحيم"
        ]
        for transcript in transcripts {
            let result = await provider.analyze(transcript: transcript, expectedWords: verse)
            XCTAssertFalse(
                result.words.contains { $0.status == .missed },
                "Correct reciter was hard-flagged on transcript: \(transcript)"
            )
        }
    }

    func testStreamingExposesActiveWordIndexAtTheHead() async {
        // After two words, the karaoke head sits on the third (next pending) word.
        let provider = HybridRecitationAnalysisProvider(useStreamingFollow: { true })
        let verse = [
            RecitationWord(originalText: "بِسْمِ"),
            RecitationWord(originalText: "ٱللَّهِ"),
            RecitationWord(originalText: "ٱلرَّحْمَٰنِ"),
            RecitationWord(originalText: "ٱلرَّحِيمِ")
        ]
        let result = await provider.analyze(transcript: "بسم الله", expectedWords: verse)
        XCTAssertEqual(result.activeWordIndex, 2)
        XCTAssertEqual(result.words[0].status, .correct)
        XCTAssertEqual(result.words[1].status, .correct)
    }

    func testNonStreamingHasNoActiveWordIndex() async {
        let provider = HybridRecitationAnalysisProvider()
        let words = [RecitationWord(originalText: "بِسْمِ"), RecitationWord(originalText: "ٱللَّهِ")]
        let result = await provider.analyze(transcript: "بسم", expectedWords: words)
        XCTAssertNil(result.activeWordIndex)
    }

    func testMistakeDetectionDefaultsOff() async {
        // Both flags must be on; default off leaves the provider unchanged.
        let provider = HybridRecitationAnalysisProvider(useStreamingFollow: { true })
        let verse = [
            RecitationWord(originalText: "بِسْمِ"),
            RecitationWord(originalText: "ٱللَّهِ"),
            RecitationWord(originalText: "ٱلرَّحْمَٰنِ"),
            RecitationWord(originalText: "ٱلرَّحِيمِ")
        ]
        let r1 = await provider.analyze(transcript: "بسم الله الرحيم", expectedWords: verse)
        let r2 = await provider.analyze(transcript: "بسم الله الرحيم", expectedWords: verse)
        // Without the mistake flag, the missed slot stays soft (.uncertain), never escalated.
        XCTAssertNotEqual(r2.words[2].status, .missed)
        XCTAssertNotEqual(r1.words[2].status, .missed)
    }
}
