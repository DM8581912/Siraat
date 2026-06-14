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
}
