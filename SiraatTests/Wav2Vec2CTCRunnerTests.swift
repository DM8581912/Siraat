import XCTest
@testable import Siraat

final class Wav2Vec2CTCRunnerTests: XCTestCase {
    func testArgmaxRowPicksMaxAndBreaksTiesLow() {
        XCTAssertEqual(Wav2Vec2CTCRunner.argmaxRow([0.1, 0.9, 0.3]), 1)
        XCTAssertEqual(Wav2Vec2CTCRunner.argmaxRow([0.5, 0.5, 0.2]), 0) // tie -> lower index
        XCTAssertEqual(Wav2Vec2CTCRunner.argmaxRow([-1.0, -2.0, -0.5]), 2)
        XCTAssertEqual(Wav2Vec2CTCRunner.argmaxRow([7.0]), 0)
    }

    func testOnDeviceFrontendDegradesGracefullyWithoutModel() {
        // No model is bundled in the test runner, so the runner returns nil and the streaming
        // frontend must simply produce no tokens — never crash, never jetsam.
        var config = StreamingCTCFrontend.Config()
        config.windowSamples = 1600
        config.hopSamples = 800
        let frontend = StreamingCTCFrontend.onDevice(bundle: Bundle(for: Self.self), config: config)
        frontend.ingest([Float](repeating: 0.01, count: 1600), sampleRate: 16_000)
        XCTAssertFalse(frontend.tick())     // infer -> nil -> no run
        XCTAssertTrue(frontend.tokens.isEmpty)
        XCTAssertEqual(frontend.ranTicks, 0)
    }

    func testRunnerReturnsNilWithoutModel() {
        let runner = Wav2Vec2CTCRunner(bundle: Bundle(for: Self.self), inputLength: 1600)
        XCTAssertNil(runner.inferPerFrame([Float](repeating: 0.0, count: 1600)))
        XCTAssertNil(runner.inferPerFrame([])) // empty guard
    }
}
