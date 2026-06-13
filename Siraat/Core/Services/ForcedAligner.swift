import AVFoundation
import CoreML
import Foundation

/// A phoneme aligned to the audio: the canonical symbol it was matched to, the base
/// Arabic letter the recognizer actually heard (equal to the canonical letter when
/// recited correctly), the start/end timestamps, and the model's confidence for that span.
struct AlignedPhoneme: Equatable, Sendable {
    let symbol: String
    let baseLetter: Character
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double

    var duration: TimeInterval { max(0, end - start) }
}

/// Result of aligning a recitation to a canonical phoneme sequence.
///
/// `harakatSeconds` is the reciter's measured duration of one harakah (the median length
/// of the short vowels the acoustic model detected). Madd grading is normalized against it
/// so it is tempo-invariant — a fast or slow reciter is judged on the *ratio* of a long
/// vowel to their own short vowels, not an absolute clock. `nil` when it cannot be measured
/// (e.g. the placeholder path or no short vowels detected), in which case the evaluator
/// falls back to the blueprint's reference durations.
struct ForcedAlignment: Equatable, Sendable {
    let phonemes: [AlignedPhoneme]
    let harakatSeconds: Double?
}

/// Maps recorded audio onto the canonical phoneme sequence of a target ayah, emitting one
/// `AlignedPhoneme` per canonical phoneme plus the measured harakah unit.
protocol PhoneticForcedAligning {
    func align(
        samples: [Float],
        sampleRate: Double,
        against blueprint: AyahPhonemeMap
    ) async throws -> ForcedAlignment
}

/// The acoustic model's phoneme vocabulary (token <-> id), loaded from the bundled
/// `phoneme_vocab.json` produced alongside the CoreML model. Falls back to the known
/// `TBOGamer22/wav2vec2-quran-phonetics` vocabulary if the file is absent, so the ids stay
/// correct for the shipped model without hardcoding being the only source of truth.
struct PhonemeVocab {
    let idToToken: [Int: String]
    let blankID: Int
    let longVowelIDs: Set<Int>   // ā ī ū — the Madd carriers
    let shortVowelIDs: Set<Int>  // a e i o u — one harakah each
    let nasalIDs: Set<Int>       // n m — the Ghunnah carriers

    private static let longVowelTokens: Set<String> = ["ā", "ī", "ū"]
    private static let shortVowelTokens: Set<String> = ["a", "e", "i", "o", "u"]
    private static let nasalTokens: Set<String> = ["n", "m"]

    init(idToToken: [Int: String]) {
        self.idToToken = idToToken
        let tokenToID = Dictionary(idToToken.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        blankID = tokenToID["[PAD]"] ?? 37
        longVowelIDs = Set(Self.longVowelTokens.compactMap { tokenToID[$0] })
        shortVowelIDs = Set(Self.shortVowelTokens.compactMap { tokenToID[$0] })
        nasalIDs = Set(Self.nasalTokens.compactMap { tokenToID[$0] })
    }

    static func load(bundle: Bundle = .main, resource: String = "phoneme_vocab") -> PhonemeVocab {
        if let url = bundle.url(forResource: resource, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let tokenToID = try? JSONDecoder().decode([String: Int].self, from: data) {
            return PhonemeVocab(idToToken: Dictionary(tokenToID.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a }))
        }
        return PhonemeVocab(idToToken: Self.fallback)
    }

    /// Verified from the CI conversion of the shipped model (see PR #14 logs).
    static let fallback: [Int: String] = [
        0: " ", 1: "'", 2: "-", 3: "H", 4: "a", 5: "b", 6: "d", 7: "e", 8: "f", 9: "g",
        10: "h", 11: "i", 12: "j", 13: "k", 14: "l", 15: "m", 16: "n", 17: "o", 18: "q",
        19: "r", 20: "s", 21: "t", 22: "u", 23: "w", 24: "y", 25: "z", 26: "ā", 27: "ī",
        28: "ū", 29: "ʿ", 30: "ḍ", 31: "ḥ", 32: "ṣ", 33: "ṭ", 34: "ẓ", 35: "|",
        36: "[UNK]", 37: "[PAD]", 38: "<s>", 39: "</s>"
    ]
}

/// On-device forced aligner backed by the Wav2Vec2 Arabic phonetic CTC model.
///
/// When `Wav2Vec2QuranPhonetics.mlmodelc` is bundled it: resamples the captured PCM to
/// 16 kHz mono, runs the model (input `[1, 160000]`, output `[1, frames, 40]` CTC logits),
/// greedy-decodes the frames into phoneme segments with real timestamps, measures the
/// harakah unit from short vowels, and matches the detected long vowels (`ā ī ū`) to the
/// blueprint's Madd positions in reading order. Consonants are intentionally left ungraded
/// (low confidence -> green) because grading them needs the model's exact consonant
/// romanization, which is not guessed in a Qur'an app. So today the model delivers real,
/// tempo-invariant **Madd-length** grading; consonant/Tashkeel grading is future work.
///
/// With no model bundled it returns a deterministic placeholder (all green), so the app
/// builds and runs without the 180 MB model. Audio never leaves the device.
final class CoreMLForcedAligner: PhoneticForcedAligning {
    private let model: MLModel?
    private let vocab: PhonemeVocab
    private let inputLength = 160_000        // 10 s @ 16 kHz, the model's fixed input
    private let sampleRateHz = 16_000.0

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "Wav2Vec2QuranPhonetics", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url)
        } else {
            model = nil
        }
        vocab = PhonemeVocab.load(bundle: bundle)
    }

    func align(
        samples: [Float],
        sampleRate: Double,
        against blueprint: AyahPhonemeMap
    ) async throws -> ForcedAlignment {
        guard let model, !samples.isEmpty else {
            return Self.placeholderAlignment(for: blueprint)
        }

        // Any inference failure degrades gracefully to the placeholder — never a crash.
        guard let decoded = (try? runModel(model, samples: samples, sampleRate: sampleRate)) ?? nil,
              !decoded.segments.isEmpty else {
            return Self.placeholderAlignment(for: blueprint)
        }

        let frameSeconds = decoded.frameSeconds
        let shortDurations = decoded.segments
            .filter { vocab.shortVowelIDs.contains($0.token) }
            .map { Double($0.length) * frameSeconds }
        let harakat = Self.median(shortDurations)

        let longDurations = decoded.segments
            .filter { vocab.longVowelIDs.contains($0.token) }
            .map { Double($0.length) * frameSeconds }
        let nasalDurations = decoded.segments
            .filter { vocab.nasalIDs.contains($0.token) }
            .map { Double($0.length) * frameSeconds }

        // Match detected long vowels to Madd positions and nasals to Ghunnah positions, both
        // in reading order. Other consonants stay below the honesty floor (left green).
        var longIndex = 0
        var nasalIndex = 0
        var cursor: TimeInterval = 0
        let phonemes: [AlignedPhoneme] = blueprint.phonemes.map { phoneme in
            func graded(_ measured: TimeInterval) -> AlignedPhoneme {
                let start = cursor
                cursor += measured
                return AlignedPhoneme(symbol: phoneme.symbol, baseLetter: phoneme.baseCharacter, start: start, end: start + measured, confidence: 0.9)
            }

            if phoneme.isMaddVowel, longIndex < longDurations.count {
                let measured = longDurations[longIndex]; longIndex += 1
                return graded(measured)
            }
            if phoneme.requiresGhunnah, nasalIndex < nasalDurations.count {
                let measured = nasalDurations[nasalIndex]; nasalIndex += 1
                return graded(measured)
            }
            // Other consonants (and unmatched Madd/Ghunnah): below the honesty floor.
            let start = cursor
            cursor += 0.05
            return AlignedPhoneme(
                symbol: phoneme.symbol,
                baseLetter: phoneme.baseCharacter,
                start: start,
                end: start + 0.05,
                confidence: 0.5
            )
        }

        return ForcedAlignment(phonemes: phonemes, harakatSeconds: harakat)
    }

    // MARK: - Inference

    private struct DecodedSegment { let token: Int; let startFrame: Int; let endFrame: Int; var length: Int { endFrame - startFrame } }
    private struct DecodeResult { let segments: [DecodedSegment]; let frameSeconds: Double }

    private func runModel(_ model: MLModel, samples: [Float], sampleRate: Double) throws -> DecodeResult? {
        // Resample -> normalize (the model expects zero-mean/unit-variance input, matching
        // the Wav2Vec2 feature extractor) -> pad/truncate to the fixed input length.
        let resampled = Self.resampleTo16k(samples, from: sampleRate, targetRate: sampleRateHz)
        let waveform = Self.fit(Self.normalize(resampled), length: inputLength)

        let input = try MLMultiArray(shape: [NSNumber(value: 1), NSNumber(value: inputLength)], dataType: .float16)
        for index in 0..<inputLength {
            input[index] = NSNumber(value: waveform[index])
        }

        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "waveform"
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)])
        let prediction = try model.prediction(from: provider)

        // Find the rank-3 logits output [1, frames, vocab] regardless of its name.
        guard let logits = prediction.featureNames
            .compactMap({ prediction.featureValue(for: $0)?.multiArrayValue })
            .first(where: { $0.shape.count == 3 })
        else { return nil }

        let frames = logits.shape[1].intValue
        let vocabCount = logits.shape[2].intValue
        guard frames > 0, vocabCount > 0 else { return nil }

        let frameStride = logits.strides[1].intValue
        let classStride = logits.strides[2].intValue

        // Greedy argmax per frame, then CTC collapse (merge repeats, drop blanks). Read via
        // the MLMultiArray linear subscript so it is correct for any output dtype/layout.
        var segments: [DecodedSegment] = []
        var runToken = -1
        var runStart = 0
        for frame in 0..<frames {
            var bestToken = 0
            var bestValue = -Double.greatestFiniteMagnitude
            let base = frame * frameStride
            for token in 0..<vocabCount {
                let value = logits[base + token * classStride].doubleValue
                if value > bestValue { bestValue = value; bestToken = token }
            }
            if bestToken != runToken {
                if runToken >= 0, runToken != vocab.blankID {
                    segments.append(DecodedSegment(token: runToken, startFrame: runStart, endFrame: frame))
                }
                runToken = bestToken
                runStart = frame
            }
        }
        if runToken >= 0, runToken != vocab.blankID {
            segments.append(DecodedSegment(token: runToken, startFrame: runStart, endFrame: frames))
        }

        // 160000 samples / frames -> seconds per frame (~20 ms for 499 frames).
        let frameSeconds = (Double(inputLength) / sampleRateHz) / Double(frames)
        return DecodeResult(segments: segments, frameSeconds: frameSeconds)
    }

    /// Resample to 16 kHz mono via linear interpolation.
    static func resampleTo16k(_ samples: [Float], from rate: Double, targetRate: Double) -> [Float] {
        guard rate > 0, abs(rate - targetRate) > 1, !samples.isEmpty else { return samples }
        let ratio = targetRate / rate
        let outCount = max(1, Int(Double(samples.count) * ratio))
        var resampled = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let src = Double(i) / ratio
            let i0 = min(Int(src), samples.count - 1)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(src - Double(i0))
            resampled[i] = samples[i0] + (samples[i1] - samples[i0]) * frac
        }
        return resampled
    }

    /// Zero-mean / unit-variance normalization (matches the Wav2Vec2 feature extractor).
    static func normalize(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let mean = samples.reduce(0, +) / Float(samples.count)
        var variance: Float = 0
        for s in samples { let d = s - mean; variance += d * d }
        variance /= Float(samples.count)
        let std = max(sqrt(variance), 1e-7)
        return samples.map { ($0 - mean) / std }
    }

    /// Pad with zeros / truncate to exactly `length` samples (keeps the start of the audio).
    static func fit(_ samples: [Float], length: Int) -> [Float] {
        if samples.count >= length { return Array(samples.prefix(length)) }
        return samples + [Float](repeating: 0, count: length - samples.count)
    }

    /// Convenience used by tests: resample then fit (no normalization, so the geometry is
    /// easy to assert).
    static func prepareWaveform(_ samples: [Float], from rate: Double, targetRate: Double, length: Int) -> [Float] {
        fit(resampleTo16k(samples, from: rate, targetRate: targetRate), length: length)
    }

    /// IEEE 754 half-precision -> Float. CoreML Float16 outputs are read as raw UInt16.
    static func float16ToFloat(_ half: UInt16) -> Float {
        let sign = UInt32(half & 0x8000) << 16
        let exponent = UInt32(half & 0x7C00) >> 10
        let mantissa = UInt32(half & 0x03FF)
        if exponent == 0 {
            if mantissa == 0 { return Float(bitPattern: sign) }
            // Subnormal: normalize.
            var e: UInt32 = 0
            var m = mantissa
            while m & 0x0400 == 0 { m <<= 1; e += 1 }
            m &= 0x03FF
            let bits = sign | ((127 - 15 - e) << 23) | (m << 13)
            return Float(bitPattern: bits)
        } else if exponent == 0x1F {
            return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13)) // inf/nan
        }
        let bits = sign | ((exponent + (127 - 15)) << 23) | (mantissa << 13)
        return Float(bitPattern: bits)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Deterministic stand-in when no model is bundled: every canonical phoneme carries its
    /// expected duration but a confidence below the honesty floor, so the evaluator grades
    /// nothing and the ayah reads all green. (No acoustic measurement happened, so claiming
    /// any verdict — good or bad — would be dishonest.)
    static func placeholderAlignment(for blueprint: AyahPhonemeMap) -> ForcedAlignment {
        var cursor: TimeInterval = 0
        let phonemes = blueprint.phonemes.map { phoneme -> AlignedPhoneme in
            let start = cursor
            let end = start + phoneme.expectedDurationSeconds
            cursor = end
            return AlignedPhoneme(
                symbol: phoneme.symbol,
                baseLetter: phoneme.baseCharacter,
                start: start,
                end: end,
                confidence: 0.5
            )
        }
        return ForcedAlignment(phonemes: phonemes, harakatSeconds: nil)
    }
}

/// Test/preview double returning a fixed alignment (or throwing).
final class MockForcedAligner: PhoneticForcedAligning {
    private let result: ForcedAlignment
    private let error: Error?

    init(result: ForcedAlignment = ForcedAlignment(phonemes: [], harakatSeconds: nil), error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func align(samples: [Float], sampleRate: Double, against blueprint: AyahPhonemeMap) async throws -> ForcedAlignment {
        if let error { throw error }
        return result
    }
}

/// Pure CTC forced-alignment math: given a per-frame emission matrix (`frames x vocab`) and
/// a target token-id sequence, find a monotonic frame span for each target token. Kept as a
/// model-independent, unit-tested routine for future consonant-level alignment once the
/// model's romanization is confirmed.
struct CTCForcedAligner {
    struct FrameSpan: Equatable {
        let startFrame: Int
        let endFrame: Int
    }

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
                spans.append(FrameSpan(startFrame: spanStart, endFrame: frame))
                tokenIndex += 1
                spanStart = frame
            }
        }

        if tokenIndex < targetTokens.count {
            spans.append(FrameSpan(startFrame: spanStart, endFrame: emissions.count))
            tokenIndex += 1
        }
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
