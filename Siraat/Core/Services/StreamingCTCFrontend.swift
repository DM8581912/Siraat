import Foundation

/// One decoded phoneme token placed on the absolute session timeline (seconds from the start
/// of the recitation), produced by streaming chunked inference.
struct StreamedToken: Equatable, Sendable {
    let token: Int
    let start: TimeInterval
    let end: TimeInterval
}

/// A fixed-capacity ring of recent 16 kHz mono audio. Memory stays flat no matter how long the
/// session runs — the oldest audio is dropped, and `baseIndex` tracks the absolute position of
/// `samples[0]` so frame timestamps stay correct across the whole session.
final class PCMRing {
    private(set) var samples: [Float] = []
    private(set) var baseIndex: Int = 0
    let capacity: Int

    init(capacity: Int) { self.capacity = max(1, capacity) }

    func append(_ new: [Float]) {
        samples.append(contentsOf: new)
        if samples.count > capacity {
            let drop = samples.count - capacity
            samples.removeFirst(drop)
            baseIndex += drop
        }
    }

    /// Absolute index one past the last sample held.
    var endIndex: Int { baseIndex + samples.count }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        baseIndex = 0
    }
}

/// Streaming, chunked on-device CTC inference over a growing audio stream.
///
/// The shipped acoustic model has a fixed 10 s input, so true frame-synchronous streaming is
/// not possible without re-exporting it. Instead this runs the model on overlapping fixed
/// windows (window = 10 s, hop ≈ 1 s) and stitches the results into one monotonically growing,
/// de-duplicated phoneme-token timeline. Three properties make it production-safe:
///
///  - **Bounded memory.** Audio lives in a fixed-capacity `PCMRing`; a 20-minute session uses
///    the same RAM as a 20-second one. (The decoded-token list grows slowly, ~one entry per
///    phoneme; callers that run for very long sessions can prune behind the alignment head.)
///  - **Back-pressure, never queue.** A tick is only honoured once at least one hop of new
///    audio has arrived since the last run; ticks that arrive sooner are dropped and counted,
///    so inference can never pile up and jetsam the app mid-recitation.
///  - **No double-emission.** The first `warmupFraction` of every window is discarded (the
///    model's left context is cold there), and only tokens that start past the committed
///    boundary of the previous window are appended — so overlapping windows never re-emit the
///    same phoneme.
///
/// The model forward-pass is injected as a closure (`infer`) — pure decoding/stitching here is
/// deterministic and unit-tested without the 90 MB model; production wires `infer` to the
/// shared Wav2Vec2 runner. Nothing about the audio ever leaves the device.
final class StreamingCTCFrontend {
    struct Config: Equatable {
        var sampleRate: Double = 16_000
        var windowSamples: Int = 160_000          // 10 s @ 16 kHz, the model's fixed input
        var hopSamples: Int = 16_000              // advance ~1 s between inferences
        var warmupFraction: Double = 0.1          // discard the first ~10% of each window
        var ringSlackSamples: Int = 16_000        // keep a little history beyond one window
    }

    let config: Config
    /// Window of 16 kHz samples -> per-frame argmax token ids (length = model frames). `nil` on
    /// inference failure (degrades to "no new tokens", never a crash).
    private let infer: ([Float]) -> [Int]?
    private let blankID: Int
    private let ring: PCMRing

    private var lastRunEndIndex = -1
    private var committedEndTime: TimeInterval = 0
    private(set) var tokens: [StreamedToken] = []
    private(set) var droppedTicks = 0
    private(set) var ranTicks = 0

    /// Current number of audio samples held in the ring (for memory assertions / diagnostics).
    var ringSampleCount: Int { ring.samples.count }

    init(
        config: Config = Config(),
        blankID: Int = PhonemeVocab.load().blankID,
        infer: @escaping ([Float]) -> [Int]?
    ) {
        self.config = config
        self.infer = infer
        self.blankID = blankID
        self.ring = PCMRing(capacity: config.windowSamples + config.ringSlackSamples)
    }

    /// Feed newly captured PCM at any sample rate; it is resampled to 16 kHz once on the way in.
    func ingest(_ samples: [Float], sampleRate inRate: Double) {
        guard !samples.isEmpty else { return }
        let s16 = CoreMLForcedAligner.resampleTo16k(samples, from: inRate, targetRate: config.sampleRate)
        ring.append(s16)
    }

    /// Run one inference pass on the latest window if a hop of new audio has accumulated.
    /// Returns true if it ran, false if it was dropped (back-pressure) or there isn't enough
    /// audio yet.
    @discardableResult
    func tick() -> Bool {
        let available = ring.endIndex
        if lastRunEndIndex >= 0, available - lastRunEndIndex < config.hopSamples {
            droppedTicks += 1
            return false
        }
        // Need at least one hop (or a full window) of audio before the first run.
        guard ring.samples.count >= min(config.windowSamples, config.hopSamples) else { return false }

        let window = Array(ring.samples.suffix(config.windowSamples))
        let windowStartAbs = ring.endIndex - window.count
        guard let perFrame = infer(window), !perFrame.isEmpty else { return false }

        let frames = perFrame.count
        let windowSeconds = Double(window.count) / config.sampleRate
        let frameSeconds = windowSeconds / Double(frames)
        let windowStartTime = Double(windowStartAbs) / config.sampleRate
        let warmupCut = windowStartTime + windowSeconds * config.warmupFraction

        // CTC collapse (merge repeats, drop blanks) into absolute-timestamped tokens.
        var decoded: [StreamedToken] = []
        var runTok = -1
        var runStart = 0
        func flush(_ endFrame: Int) {
            guard runTok >= 0, runTok != blankID, endFrame > runStart else { return }
            decoded.append(
                StreamedToken(
                    token: runTok,
                    start: windowStartTime + Double(runStart) * frameSeconds,
                    end: windowStartTime + Double(endFrame) * frameSeconds
                )
            )
        }
        for (frame, tok) in perFrame.enumerated() where tok != runTok {
            flush(frame); runTok = tok; runStart = frame
        }
        flush(frames)

        // Append only tokens that begin past the committed boundary and the warm-up region.
        let boundary = max(committedEndTime, warmupCut)
        let accepted = decoded.filter { $0.start >= boundary }
        tokens.append(contentsOf: accepted)
        committedEndTime = max(committedEndTime, decoded.last?.end ?? committedEndTime)
        lastRunEndIndex = available
        ranTicks += 1
        return true
    }

    func reset() {
        ring.reset()
        tokens.removeAll(keepingCapacity: true)
        lastRunEndIndex = -1
        committedEndTime = 0
        droppedTicks = 0
        ranTicks = 0
    }
}
