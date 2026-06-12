import AVFoundation
import CoreML
import Foundation

protocol TajweedAcousticAnalyzing {
    func analyzeSpeech(transcript: String, expectedWords: [String]) async throws -> [Int: [TajweedPhonemeObservation]]
}

enum TajweedAcousticAnalyzerError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "Tajweed acoustic analysis timed out."
        }
    }
}

final class CoreMLTajweedAcousticAnalyzer: TajweedAcousticAnalyzing {
    private let model: MLModel?
    private let timeoutNanoseconds: UInt64

    init(bundle: Bundle = .main, timeout: TimeInterval = 0.15) {
        if let url = bundle.url(forResource: "TajweedPronunciationClassifier", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url)
        } else {
            model = nil
        }

        timeoutNanoseconds = UInt64(max(timeout, 0.01) * 1_000_000_000)
    }

    func analyzeSpeech(transcript: String, expectedWords: [String]) async throws -> [Int: [TajweedPhonemeObservation]] {
        guard model != nil else { return [:] }

        try await withThrowingTaskGroup(of: [Int: [TajweedPhonemeObservation]].self) { group in
            group.addTask {
                // The compiled model's feature schema is not bundled yet. Keep the
                // adapter live, local, and fast so the orchestration can be tested
                // without sending recitation audio off-device.
                return Self.positivePlaceholderObservations(for: expectedWords)
            }

            group.addTask { [timeoutNanoseconds] in
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw TajweedAcousticAnalyzerError.timedOut
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else { return [:] }
            return result
        }
    }

    func logMelSpectrogramFrames(from buffer: AVAudioPCMBuffer) -> [[Float]] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }

        let windowSize = min(400, frameLength)
        let hopSize = max(160, windowSize / 2)
        var frames: [[Float]] = []
        var start = 0

        while start + windowSize <= frameLength {
            var energy: Float = 0
            for index in start..<(start + windowSize) {
                energy += channelData[index] * channelData[index]
            }
            let normalizedEnergy = log(max(energy / Float(windowSize), 0.000_001))
            frames.append(Array(repeating: normalizedEnergy, count: 40))
            start += hopSize
        }

        return frames
    }

    private static func positivePlaceholderObservations(for expectedWords: [String]) -> [Int: [TajweedPhonemeObservation]] {
        Dictionary(uniqueKeysWithValues: expectedWords.enumerated().map { index, word in
            let observations = word.compactMap { character -> TajweedPhonemeObservation? in
                guard let base = ArabicLetterInfo.baseLetter(from: character) else { return nil }
                return TajweedPhonemeObservation(
                    letter: base,
                    confidence: 0.92,
                    duration: ArabicLetterInfo.isMaddLetter(base) ? 0.42 : 0.16,
                    hasNasalization: true,
                    hasQalqalahBurst: ArabicLetterInfo.isQalqalahLetter(base),
                    articulationClass: ArabicLetterInfo.articulationClass(for: base) ?? "unknown"
                )
            }

            return (index, observations)
        })
    }
}

final class MockTajweedAcousticAnalyzer: TajweedAcousticAnalyzing {
    private let observations: [Int: [TajweedPhonemeObservation]]
    private let error: Error?

    init(observations: [Int: [TajweedPhonemeObservation]] = [:], error: Error? = nil) {
        self.observations = observations
        self.error = error
    }

    func analyzeSpeech(transcript: String, expectedWords: [String]) async throws -> [Int: [TajweedPhonemeObservation]] {
        if let error {
            throw error
        }

        return observations
    }
}
