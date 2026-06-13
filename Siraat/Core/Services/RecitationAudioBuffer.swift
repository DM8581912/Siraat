import AVFoundation
import Foundation

/// A thread-safe accumulator of mono PCM samples captured from the microphone tap.
///
/// The `AudioStreamManager` tap runs on the real-time audio thread; it only ever calls
/// `append(_:)`, which copies samples under a lock and returns immediately. The aligner
/// reads a `snapshot()` when a recitation segment finalizes. Audio never leaves the
/// device — this buffer is the on-device handoff between capture and the CoreML aligner.
final class RecitationAudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var storedSampleRate: Double
    private let maxSamples: Int

    init(maxSeconds: Double = 30, assumedSampleRate: Double = 48_000) {
        storedSampleRate = assumedSampleRate
        maxSamples = max(1, Int(maxSeconds * assumedSampleRate))
    }

    /// Copies the first channel of `buffer`. Safe to call from the audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        let incoming = Array(UnsafeBufferPointer(start: channel, count: frames))
        let rate = buffer.format.sampleRate

        lock.lock()
        defer { lock.unlock() }
        if rate > 0 { storedSampleRate = rate }
        samples.append(contentsOf: incoming)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    func snapshot() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (samples, storedSampleRate)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
    }
}
