import CoreML
import Foundation

/// Shared on-device Wav2Vec2 phoneme CTC inference: a 16 kHz window in, per-frame argmax token
/// ids out. This is the model forward-pass that feeds `StreamingCTCFrontend`'s streaming decode
/// — the thing that lets the follow-along track the *sound* of the recitation.
///
/// It mirrors the proven preprocessing + logits-reading of `CoreMLForcedAligner` (reusing its
/// static helpers) but returns the raw per-frame argmax so the frontend can do the streaming
/// CTC collapse + stitching. Loaded lazily off the main actor; returns nil when no model is
/// bundled or inference fails, so the streaming path degrades to "no new tokens" rather than
/// crashing or jetsamming. Audio never leaves the device.
final class Wav2Vec2CTCRunner {
    private let modelURL: URL?
    private let inputLength: Int
    private let loadLock = NSLock()
    private var loadedModel: MLModel?
    private var didAttemptLoad = false

    init(bundle: Bundle = .main, inputLength: Int = 160_000) {
        self.modelURL = bundle.url(forResource: "Wav2Vec2QuranPhonetics", withExtension: "mlmodelc")
        self.inputLength = inputLength
    }

    private func model() -> MLModel? {
        loadLock.lock()
        defer { loadLock.unlock() }
        if didAttemptLoad { return loadedModel }
        didAttemptLoad = true
        guard let modelURL else { return nil }
        let config = MLModelConfiguration()
        // Same compute-unit choice as the one-shot aligner: a smaller, more predictable peak on
        // a sideloaded build (the jetsam-safe path, see PR #17).
        config.computeUnits = .cpuAndNeuralEngine
        loadedModel = try? MLModel(contentsOf: modelURL, configuration: config)
        return loadedModel
    }

    /// 16 kHz samples (any length; normalized + fit to the model's fixed input) -> per-frame
    /// argmax token ids, or nil when no model is available / inference fails.
    func inferPerFrame(_ window: [Float]) -> [Int]? {
        guard !window.isEmpty, let model = model() else { return nil }
        let waveform = CoreMLForcedAligner.fit(CoreMLForcedAligner.normalize(window), length: inputLength)

        guard let input = try? MLMultiArray(shape: [NSNumber(value: 1), NSNumber(value: inputLength)], dataType: .float16) else {
            return nil
        }
        for index in 0..<inputLength { input[index] = NSNumber(value: waveform[index]) }

        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "waveform"
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)]),
              let prediction = try? model.prediction(from: provider),
              let logits = prediction.featureNames
                  .compactMap({ prediction.featureValue(for: $0)?.multiArrayValue })
                  .first(where: { $0.shape.count == 3 })
        else { return nil }

        let frames = logits.shape[1].intValue
        let vocab = logits.shape[2].intValue
        guard frames > 0, vocab > 0 else { return nil }
        let frameStride = logits.strides[1].intValue
        let classStride = logits.strides[2].intValue

        var out = [Int](repeating: 0, count: frames)
        var row = [Double](repeating: 0, count: vocab)
        for frame in 0..<frames {
            let base = frame * frameStride
            for token in 0..<vocab { row[token] = logits[base + token * classStride].doubleValue }
            out[frame] = Self.argmaxRow(row)
        }
        return out
    }

    /// Index of the maximum logit in a frame (ties resolved to the lower index, like the CTC
    /// greedy decode). Pure and unit-tested; `inferPerFrame` uses exactly this.
    static func argmaxRow(_ row: [Double]) -> Int {
        var best = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for token in row.indices where row[token] > bestValue {
            bestValue = row[token]
            best = token
        }
        return best
    }
}

extension StreamingCTCFrontend {
    /// Build a frontend wired to the real on-device model. CI-safe: with no model bundled the
    /// runner returns nil and the frontend simply produces no tokens.
    static func onDevice(bundle: Bundle = .main, config: Config = Config()) -> StreamingCTCFrontend {
        let runner = Wav2Vec2CTCRunner(bundle: bundle, inputLength: config.windowSamples)
        let vocab = PhonemeVocab.load(bundle: bundle)
        return StreamingCTCFrontend(config: config, blankID: vocab.blankID, infer: { runner.inferPerFrame($0) })
    }
}
