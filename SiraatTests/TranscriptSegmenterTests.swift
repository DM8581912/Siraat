import XCTest
@testable import Siraat

final class TranscriptSegmenterTests: XCTestCase {
    func testEmitsCompletedArabicSentenceOnce() {
        var segmenter = TranscriptSegmenter()

        let first = segmenter.consume("الحمد لله رب العالمين", isFinal: false)
        let second = segmenter.consume("الحمد لله رب العالمين. اتقوا الله", isFinal: false)
        let third = segmenter.consume("الحمد لله رب العالمين. اتقوا الله", isFinal: true)

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, ["الحمد لله رب العالمين."])
        XCTAssertEqual(third, ["اتقوا الله"])
    }

    func testSupportsArabicQuestionMark() {
        var segmenter = TranscriptSegmenter()

        let segments = segmenter.consume("أفلا تتقون؟ ثم", isFinal: false)

        XCTAssertEqual(segments, ["أفلا تتقون؟"])
    }

    func testResetsWhenRecognizerTranscriptShrinks() {
        var segmenter = TranscriptSegmenter()

        _ = segmenter.consume("بسم الله.", isFinal: false)
        let segments = segmenter.consume("الحمد لله.", isFinal: false)

        XCTAssertEqual(segments, ["الحمد لله."])
    }
}
