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
}
