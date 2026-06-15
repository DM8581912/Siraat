import XCTest
@testable import Siraat

final class CharacterTajweedEvaluatorTests: XCTestCase {
    // "بَا": cluster 0 = ب (consonant), cluster 1 = ا (Madd vowel).
    private let uthmani = "بَا"

    private func blueprint() -> AyahPhonemeMap {
        AyahPhonemeMap(
            verseKey: "test:1",
            scriptUthmani: uthmani,
            source: BlueprintProvenance(corpus: "test", attribution: "test", verified: true),
            phonemes: [
                CanonicalPhoneme(symbol: "b", baseLetter: "ب", isMaddVowel: false, expectedMaddCount: 0, expectedDurationSeconds: 0.18),
                CanonicalPhoneme(symbol: "A", baseLetter: "ا", isMaddVowel: true, expectedMaddCount: 2, expectedDurationSeconds: 0.9)
            ]
        )
    }

    private func phoneme(_ base: Character, start: Double, end: Double, confidence: Double) -> AlignedPhoneme {
        AlignedPhoneme(symbol: String(base), baseLetter: base, start: start, end: end, confidence: confidence)
    }

    private func alignment(_ phonemes: [AlignedPhoneme], harakat: Double? = nil) -> ForcedAlignment {
        ForcedAlignment(phonemes: phonemes, harakatSeconds: harakat)
    }

    func testCorrectRecitationIsAllGreen() {
        let a = alignment([
            phoneme("ب", start: 0, end: 0.18, confidence: 0.9),
            phoneme("ا", start: 0.18, end: 1.08, confidence: 0.9)
        ])
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results.map(\.color), [.green, .green])
        XCTAssertEqual(results.compactMap(\.errorType), [])
    }

    func testShortMaddIsYellow() {
        let a = alignment([
            phoneme("ب", start: 0, end: 0.18, confidence: 0.9),
            phoneme("ا", start: 0.18, end: 0.48, confidence: 0.9) // 0.30s < 0.9*0.5
        ])
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results[1].color, .yellow)
        XCTAssertEqual(results[1].errorType, .maddShort)
    }

    func testTempoNormalizedShortMaddUsesMeasuredHarakah() {
        // Fast reciter: 1 harakah = 0.15s, so a natural Madd should be >= ~0.3s.
        // A 0.12s long vowel is below 1 harakah -> flagged, independent of the blueprint clock.
        let a = alignment([
            phoneme("ب", start: 0, end: 0.10, confidence: 0.9),
            phoneme("ا", start: 0.10, end: 0.22, confidence: 0.9) // 0.12s
        ], harakat: 0.15)
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results[1].errorType, .maddShort)
    }

    func testTempoNormalizedAdequateMaddIsGreen() {
        // Same fast tempo, but the Madd is held 0.40s (> 2 harakāt) -> correct.
        let a = alignment([
            phoneme("ب", start: 0, end: 0.10, confidence: 0.9),
            phoneme("ا", start: 0.10, end: 0.50, confidence: 0.9) // 0.40s
        ], harakat: 0.15)
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results[1].color, .green)
        XCTAssertNil(results[1].errorType)
    }

    private func blueprint(maddCount: Int) -> AyahPhonemeMap {
        AyahPhonemeMap(
            verseKey: "test:1",
            scriptUthmani: uthmani,
            source: BlueprintProvenance(corpus: "test", attribution: "test", verified: true),
            phonemes: [
                CanonicalPhoneme(symbol: "b", baseLetter: "ب", isMaddVowel: false, expectedMaddCount: 0, expectedDurationSeconds: 0.18),
                CanonicalPhoneme(symbol: "A", baseLetter: "ا", isMaddVowel: true, expectedMaddCount: maddCount, expectedDurationSeconds: 0.9)
            ]
        )
    }

    func testLazimMaddHeldOnlyTwoCountsIsFlaggedShort() {
        // A 6-count Lāzim recited at 2 counts. harakah 0.2s -> 2 counts = 0.40s,
        // far below the required ~6 counts. A fixed 2-count check would wrongly pass it.
        let a = alignment([
            phoneme("ب", start: 0, end: 0.20, confidence: 0.9),
            phoneme("ا", start: 0.20, end: 0.60, confidence: 0.9) // 0.40s = 2 harakāt
        ], harakat: 0.2)
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(maddCount: 6), alignment: a)
        XCTAssertEqual(results[1].color, .yellow)
        XCTAssertEqual(results[1].errorType, .maddShort)
    }

    func testLazimMaddHeldSixCountsIsGreen() {
        // Same Lāzim held the required 6 counts (1.20s at 0.2s/harakah) -> correct.
        let a = alignment([
            phoneme("ب", start: 0, end: 0.20, confidence: 0.9),
            phoneme("ا", start: 0.20, end: 1.40, confidence: 0.9) // 1.20s = 6 harakāt
        ], harakat: 0.2)
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(maddCount: 6), alignment: a)
        XCTAssertEqual(results[1].color, .green)
        XCTAssertNil(results[1].errorType)
    }

    func testMissingPhonemeIsRedMissed() {
        let a = alignment([phoneme("ب", start: 0, end: 0.18, confidence: 0.9)])
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results[1].color, .red)
        XCTAssertEqual(results[1].errorType, .missed)
    }

    func testWrongLetterAtHighConfidenceIsRed() {
        let a = alignment([
            phoneme("ت", start: 0, end: 0.18, confidence: 0.95), // heard ت instead of ب
            phoneme("ا", start: 0.18, end: 1.08, confidence: 0.9)
        ])
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results[0].color, .red)
        XCTAssertEqual(results[0].errorType, .tashkeelWrong)
    }

    func testLowConfidenceWrongLetterStaysGreen() {
        // Honesty regression guard: we never flag what we cannot confidently hear.
        let a = alignment([
            phoneme("ت", start: 0, end: 0.18, confidence: 0.45),
            phoneme("ا", start: 0.18, end: 1.08, confidence: 0.45)
        ])
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results.map(\.color), [.green, .green])
        XCTAssertEqual(results.compactMap(\.errorType), [])
    }

    func testResultRangesCoverEachCluster() {
        let a = CoreMLForcedAligner.placeholderAlignment(for: blueprint())
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), alignment: a)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].utf16Range.lowerBound, 0)
        XCTAssertEqual(results.last?.utf16Range.upperBound, (uthmani as NSString).length)
    }
}
