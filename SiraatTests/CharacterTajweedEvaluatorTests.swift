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

    func testCorrectRecitationIsAllGreen() {
        let aligned = [
            phoneme("ب", start: 0, end: 0.18, confidence: 0.9),
            phoneme("ا", start: 0.18, end: 1.08, confidence: 0.9)
        ]
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), aligned: aligned)
        XCTAssertEqual(results.map(\.color), [.green, .green])
        XCTAssertEqual(results.compactMap(\.errorType), [])
    }

    func testShortMaddIsYellow() {
        let aligned = [
            phoneme("ب", start: 0, end: 0.18, confidence: 0.9),
            phoneme("ا", start: 0.18, end: 0.48, confidence: 0.9) // 0.30s < 0.9*0.5
        ]
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), aligned: aligned)
        XCTAssertEqual(results[1].color, .yellow)
        XCTAssertEqual(results[1].errorType, .maddShort)
    }

    func testMissingPhonemeIsRedMissed() {
        let aligned = [phoneme("ب", start: 0, end: 0.18, confidence: 0.9)]
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), aligned: aligned)
        XCTAssertEqual(results[1].color, .red)
        XCTAssertEqual(results[1].errorType, .missed)
    }

    func testWrongLetterAtHighConfidenceIsRed() {
        let aligned = [
            phoneme("ت", start: 0, end: 0.18, confidence: 0.95), // heard ت instead of ب
            phoneme("ا", start: 0.18, end: 1.08, confidence: 0.9)
        ]
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), aligned: aligned)
        XCTAssertEqual(results[0].color, .red)
        XCTAssertEqual(results[0].errorType, .tashkeelWrong)
    }

    func testLowConfidenceWrongLetterStaysGreen() {
        // Honesty regression guard: we never flag what we cannot confidently hear.
        let aligned = [
            phoneme("ت", start: 0, end: 0.18, confidence: 0.45),
            phoneme("ا", start: 0.18, end: 1.08, confidence: 0.45)
        ]
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), aligned: aligned)
        XCTAssertEqual(results.map(\.color), [.green, .green])
        XCTAssertEqual(results.compactMap(\.errorType), [])
    }

    func testResultRangesCoverEachCluster() {
        let aligned = CoreMLForcedAligner.placeholderAlignment(for: blueprint())
        let results = CharacterTajweedEvaluator().evaluate(uthmani: uthmani, blueprint: blueprint(), aligned: aligned)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].utf16Range.lowerBound, 0)
        XCTAssertEqual(results.last?.utf16Range.upperBound, (uthmani as NSString).length)
    }
}
