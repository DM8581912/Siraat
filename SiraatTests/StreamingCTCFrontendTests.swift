import XCTest
@testable import Siraat

/// The streaming chunked-inference orchestration is the bug-prone part of "track live audio
/// with bounded latency" — windowing, stitching, back-pressure, memory. These tests pin all of
/// it deterministically with an injected fake inference (no model, no audio), so the behavior
/// is proven in CI.
final class StreamingCTCFrontendTests: XCTestCase {
    private let blank = 37

    /// A fake forward-pass that returns a prescribed per-frame token sequence regardless of the
    /// audio, so timestamps and stitching are fully determined.
    private func fixedInfer(_ frames: [Int]) -> ([Float]) -> [Int]? {
        { _ in frames }
    }

    private func config(window: Int, hop: Int, warmup: Double = 0) -> StreamingCTCFrontend.Config {
        var c = StreamingCTCFrontend.Config()
        c.windowSamples = window
        c.hopSamples = hop
        c.warmupFraction = warmup
        c.ringSlackSamples = hop
        return c
    }

    // MARK: PCMRing

    func testPCMRingIsBoundedAndTracksAbsolutePosition() {
        let ring = PCMRing(capacity: 1000)
        ring.append([Float](repeating: 0, count: 600))
        ring.append([Float](repeating: 0, count: 600))
        XCTAssertEqual(ring.samples.count, 1000)     // bounded
        XCTAssertEqual(ring.baseIndex, 200)          // dropped the oldest 200
        XCTAssertEqual(ring.endIndex, 1200)          // absolute end is unaffected by dropping
    }

    // MARK: Decode + timestamps

    func testDecodesCollapsedTokensWithAbsoluteTimestamps() {
        let frontend = StreamingCTCFrontend(
            config: config(window: 1600, hop: 1600),
            blankID: blank,
            infer: fixedInfer([1, 1, 1, 37, 2, 2]) // 6 frames over a 0.1s window -> ~0.01667s/frame
        )
        frontend.ingest([Float](repeating: 0.01, count: 1600), sampleRate: 16_000) // 0.1s
        XCTAssertTrue(frontend.tick())

        XCTAssertEqual(frontend.tokens.count, 2) // the blank run is dropped
        XCTAssertEqual(frontend.tokens[0].token, 1)
        XCTAssertEqual(frontend.tokens[0].start, 0, accuracy: 1e-6)
        XCTAssertEqual(frontend.tokens[0].end, 0.05, accuracy: 1e-3)   // 3 frames
        XCTAssertEqual(frontend.tokens[1].token, 2)
        XCTAssertEqual(frontend.tokens[1].end, 0.1, accuracy: 1e-3)    // window end
    }

    // MARK: Back-pressure

    func testTickIsDroppedUntilAHopOfNewAudioArrives() {
        let frontend = StreamingCTCFrontend(
            config: config(window: 1600, hop: 1600),
            blankID: blank,
            infer: fixedInfer([1, 1])
        )
        frontend.ingest([Float](repeating: 0.01, count: 1600), sampleRate: 16_000)
        XCTAssertTrue(frontend.tick())           // first run
        XCTAssertEqual(frontend.ranTicks, 1)

        frontend.ingest([Float](repeating: 0.01, count: 100), sampleRate: 16_000) // < 1 hop
        XCTAssertFalse(frontend.tick())          // dropped — would have re-run the same audio
        XCTAssertEqual(frontend.droppedTicks, 1)
        XCTAssertEqual(frontend.ranTicks, 1)

        frontend.ingest([Float](repeating: 0.01, count: 1600), sampleRate: 16_000) // a full hop
        XCTAssertTrue(frontend.tick())
        XCTAssertEqual(frontend.ranTicks, 2)
    }

    // MARK: Stitching across overlapping windows

    func testOverlappingWindowsProduceAMonotonicNonDuplicatedTimeline() {
        let frontend = StreamingCTCFrontend(
            config: config(window: 1600, hop: 800), // 50% overlap
            blankID: blank,
            infer: fixedInfer([3, 3, 37, 4, 4, 37, 5, 5])
        )
        // Feed 1 second of audio in hop-sized chunks, ticking after each.
        for _ in 0..<12 {
            frontend.ingest([Float](repeating: 0.02, count: 800), sampleRate: 16_000)
            frontend.tick()
        }
        XCTAssertGreaterThan(frontend.tokens.count, 0)
        // Monotonic: each token starts no earlier than the previous one (stitching never goes
        // backwards), and no two appended tokens share the exact same (token, start) — i.e. the
        // overlap region is not double-emitted.
        var seen = Set<String>()
        for i in frontend.tokens.indices {
            if i > 0 {
                XCTAssertGreaterThanOrEqual(
                    frontend.tokens[i].start, frontend.tokens[i - 1].start - 1e-9,
                    "Timeline went backwards at \(i)"
                )
            }
            let key = "\(frontend.tokens[i].token):\(Int(frontend.tokens[i].start * 1000))"
            XCTAssertFalse(seen.contains(key), "Double-emitted token \(key)")
            seen.insert(key)
        }
    }

    // MARK: Memory bound

    func testMemoryStaysFlatAcrossALongSession() {
        let frontend = StreamingCTCFrontend(
            config: config(window: 1600, hop: 800),
            blankID: blank,
            infer: fixedInfer([1, 37, 2])
        )
        // Push ~30 seconds of audio (far more than one window) in chunks.
        for _ in 0..<600 {
            frontend.ingest([Float](repeating: 0.0, count: 800), sampleRate: 16_000)
            frontend.tick()
        }
        // The audio ring never exceeds its capacity regardless of session length.
        XCTAssertLessThanOrEqual(frontend.ringSampleCount, 1600 + 800)
    }

    func testResetClearsEverything() {
        let frontend = StreamingCTCFrontend(
            config: config(window: 1600, hop: 1600),
            blankID: blank,
            infer: fixedInfer([1, 1])
        )
        frontend.ingest([Float](repeating: 0.01, count: 1600), sampleRate: 16_000)
        frontend.tick()
        XCTAssertFalse(frontend.tokens.isEmpty)
        frontend.reset()
        XCTAssertTrue(frontend.tokens.isEmpty)
        XCTAssertEqual(frontend.ranTicks, 0)
        XCTAssertEqual(frontend.droppedTicks, 0)
    }
}
