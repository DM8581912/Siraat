import XCTest
@testable import Siraat

final class ForcedAlignerTests: XCTestCase {
    private func blueprint() -> AyahPhonemeMap {
        AyahPhonemeMap(
            verseKey: "test:1",
            scriptUthmani: "بَا",
            source: BlueprintProvenance(corpus: "test", attribution: "test", verified: true),
            phonemes: [
                CanonicalPhoneme(symbol: "b", baseLetter: "ب", isMaddVowel: false, expectedMaddCount: 0, expectedDurationSeconds: 0.18),
                CanonicalPhoneme(symbol: "A", baseLetter: "ا", isMaddVowel: true, expectedMaddCount: 2, expectedDurationSeconds: 0.9)
            ]
        )
    }

    func testPlaceholderAlignmentMatchesBlueprintAndReadsGreen() async throws {
        let aligner = CoreMLForcedAligner()
        let alignment = try await aligner.align(samples: [], sampleRate: 16_000, against: blueprint())
        XCTAssertEqual(alignment.phonemes.count, 2)
        XCTAssertEqual(alignment.phonemes[0].baseLetter, "ب")
        XCTAssertEqual(alignment.phonemes[1].duration, 0.9, accuracy: 0.0001)
        XCTAssertNil(alignment.harakatSeconds)

        // The placeholder must never invent an error.
        let results = CharacterTajweedEvaluator().evaluate(uthmani: "بَا", blueprint: blueprint(), alignment: alignment)
        XCTAssertEqual(results.map(\.color), [.green, .green])
    }

    func testHybridProviderProducesGreenWithoutModel() async {
        let provider = HybridRecitationAnalysisProvider()
        let results = await provider.analyzeCharacters(
            uthmani: "بَا",
            blueprint: blueprint(),
            samples: [],
            sampleRate: 16_000
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.color), [.green, .green])
    }

    func testDefaultProviderReturnsNoCharacterResults() async {
        struct WordsOnlyProvider: RecitationAnalysisProviding {
            func analyze(transcript: String, expectedWords: [RecitationWord]) async -> RecitationAnalysisResult {
                RecitationAnalysisResult(words: expectedWords, engine: .localMatcher)
            }
        }
        let results = await WordsOnlyProvider().analyzeCharacters(
            uthmani: "بَا",
            blueprint: blueprint(),
            samples: [],
            sampleRate: 16_000
        )
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Pure helpers (no model needed)

    func testFloat16RoundTrip() {
        for value in [0.0 as Float, 1.0, -1.0, 0.5, 2.5, -3.75, 0.02004] {
            let half = Self.floatToFloat16(value)
            let back = CoreMLForcedAligner.float16ToFloat(half)
            XCTAssertEqual(back, value, accuracy: 0.01, "round-trip failed for \(value)")
        }
    }

    func testMedian() {
        XCTAssertNil(CoreMLForcedAligner.median([]))
        XCTAssertEqual(CoreMLForcedAligner.median([0.2]), 0.2)
        XCTAssertEqual(CoreMLForcedAligner.median([0.1, 0.3]), 0.2, accuracy: 1e-9)
        XCTAssertEqual(CoreMLForcedAligner.median([0.3, 0.1, 0.2]), 0.2, accuracy: 1e-9)
    }

    func testPrepareWaveformPadsAndTruncatesToFixedLength() {
        // Short input is zero-padded to the model's fixed length.
        let short = CoreMLForcedAligner.prepareWaveform([1, 1, 1], from: 16_000, targetRate: 16_000, length: 10)
        XCTAssertEqual(short.count, 10)
        XCTAssertEqual(short.suffix(5), [0, 0, 0, 0, 0])

        // Long input is truncated to the first `length` samples.
        let long = CoreMLForcedAligner.prepareWaveform(Array(repeating: 1, count: 50), from: 16_000, targetRate: 16_000, length: 10)
        XCTAssertEqual(long.count, 10)
    }

    func testPrepareWaveformResamplesByRateRatio() {
        // 48 kHz -> 16 kHz is a 1/3 decimation; 30 input samples -> ~10 at 16 kHz.
        let out = CoreMLForcedAligner.prepareWaveform(Array(repeating: 0.5, count: 30), from: 48_000, targetRate: 16_000, length: 100)
        // Padded to 100, but the resampled body should be ~10 non-trivial samples.
        XCTAssertEqual(out.count, 100)
        XCTAssertEqual(out[0], 0.5, accuracy: 1e-6)
    }

    // Minimal Float -> Float16 bit packing for the round-trip test.
    private static func floatToFloat16(_ value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        let exp = Int((bits >> 23) & 0xFF) - 127 + 15
        let mantissa = bits & 0x7F_FFFF
        if exp <= 0 { return sign }
        if exp >= 0x1F { return sign | 0x7C00 }
        return sign | UInt16(exp << 10) | UInt16(mantissa >> 13)
    }
}
