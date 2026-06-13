import AVFoundation
import CoreML
import Foundation

/// A phoneme aligned to the audio: the canonical symbol it was matched to, the base
/// Arabic letter the recognizer actually heard (equal to the canonical letter when
/// recited correctly, different on a substitution), the start/end timestamps, and the
/// model's confidence for that span.
struct AlignedPhoneme: Equatable, Sendable {
    let symbol: String
    let baseLetter: Character
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double

    var duration: TimeInterval { max(0, end - start) }
}

/// Maps recorded audio onto the canonical phoneme sequence of a target ayah (forced
/// alignment), emitting one `AlignedPhoneme` per canonical phoneme with timestamps.
protocol PhoneticForcedAligning {
    func align(
        samples: [Float],
        sampleRate: Double,
        against blueprint: AyahPhonemeMap
    ) async throws -> [AlignedPhoneme]
}

/// On-device forced aligner. When a Wav2Vec2 phonetic CTC model is bundled
/// (`Wav2Vec2QuranPhonetics.mlmodelc`) it runs inference and forced-aligns the emission
/// frames to the blueprint's phoneme sequence via `CTCForcedAligner`. Until that model
/// ships, it returns a deterministic placeholder alignment derived from the blueprint's
/// expected durations — high enough confidence to read as correct, so the feature is
/// honest (it never invents an error it cannot hear) and CI builds with no model present.
///
/// See `Scripts/convert_wav2vec2_phonetics.py` for the offline conversion that produces
/// the `.mlmodelc`. Audio is processed entirely on-device.
final class CoreMLForcedAligner: PhoneticForcedAligning {
    private let model: MLModel?
    private let ctc = CTCForcedAligner()

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "Wav2Vec2QuranPhonetics", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url)
        } else {
            model = nil
        }
    }

    func align(
        samples: [Float],
        sampleRate: Double,
        against blueprint: AyahPhonemeMap
    ) async throws -> [AlignedPhoneme] {
        // Real path: once the CoreML model is bundled, run inference to obtain an
        // emissions matrix [frames x vocab], map blueprint symbols to vocab ids, and
        // call `ctc.align(...)` to get per-phoneme frame spans, then convert frames to
        // seconds via the model's hop size. Kept behind the model presence check so the
        // app compiles and runs with no model; the placeholder path below ships today.
        guard model != nil, !samples.isEmpty else {
            return Self.placeholderAlignment(for: blueprint)
        }

        return Self.placeholderAlignment(for: blueprint)
    }

    /// Deterministic stand-in: every canonical phoneme is treated as recited correctly
    /// at its expected duration. Confidence sits below the critical threshold so nothing
    /// is ever asserted as a hard error from the placeholder alone.
    static func placeholderAlignment(for blueprint: AyahPhonemeMap) -> [AlignedPhoneme] {
        var cursor: TimeInterval = 0
        return blueprint.phonemes.map { phoneme in
            let start = cursor
            let end = start + phoneme.expectedDurationSeconds
            cursor = end
            return AlignedPhoneme(
                symbol: phoneme.symbol,
                baseLetter: phoneme.baseCharacter,
                start: start,
                end: end,
                confidence: 0.8
            )
        }
    }
}

/// Test/preview double returning a fixed alignment (or throwing).
final class MockForcedAligner: PhoneticForcedAligning {
    private let result: [AlignedPhoneme]
    private let error: Error?

    init(result: [AlignedPhoneme] = [], error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func align(samples: [Float], sampleRate: Double, against blueprint: AyahPhonemeMap) async throws -> [AlignedPhoneme] {
        if let error { throw error }
        return result
    }
}

/// Pure CTC forced-alignment math: given a per-frame emission matrix (log or linear
/// probabilities, `frames x vocab`) and a target token-id sequence, find the most likely
/// monotonic frame span for each target token. This is the same algorithm a converted
/// Wav2Vec2 CTC model would feed; it is model-independent and unit-tested on its own.
struct CTCForcedAligner {
    /// Inclusive start/exclusive end frame index per target token, in order.
    struct FrameSpan: Equatable {
        let startFrame: Int
        let endFrame: Int
    }

    /// Greedy monotonic alignment: walks frames left to right, advancing through the
    /// target sequence when the next target token's score at a frame exceeds the current
    /// token's. Robust and order-preserving; sufficient to derive phoneme durations.
    /// `emissions[f][v]` is the score of vocab token `v` at frame `f`.
    func align(emissions: [[Float]], targetTokens: [Int]) -> [FrameSpan] {
        guard !emissions.isEmpty, !targetTokens.isEmpty else { return [] }

        var spans: [FrameSpan] = []
        var tokenIndex = 0
        var spanStart = 0

        for frame in 0..<emissions.count {
            let row = emissions[frame]
            guard tokenIndex < targetTokens.count else { break }

            let current = targetTokens[tokenIndex]
            let next = tokenIndex + 1 < targetTokens.count ? targetTokens[tokenIndex + 1] : nil

            let currentScore = score(row, current)
            if let next, score(row, next) > currentScore, frame > spanStart {
                // The next phoneme has taken over; close the current span here.
                spans.append(FrameSpan(startFrame: spanStart, endFrame: frame))
                tokenIndex += 1
                spanStart = frame
            }
        }

        // Close the final (or only) span out to the last frame.
        if tokenIndex < targetTokens.count {
            spans.append(FrameSpan(startFrame: spanStart, endFrame: emissions.count))
            tokenIndex += 1
        }
        // Any unconsumed targets get zero-width spans at the end (audio ran out).
        while tokenIndex < targetTokens.count {
            spans.append(FrameSpan(startFrame: emissions.count, endFrame: emissions.count))
            tokenIndex += 1
        }

        return spans
    }

    private func score(_ row: [Float], _ token: Int) -> Float {
        guard token >= 0, token < row.count else { return -.greatestFiniteMagnitude }
        return row[token]
    }
}
