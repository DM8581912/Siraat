import XCTest
@testable import Siraat

final class ArabicTextNormalizerTests: XCTestCase {
    func testNormalizeRemovesDiacriticsAndNormalizesAlefForms() {
        let input = "ٱلْحَمْدُ لِلَّهِ أَكْبَرُ"

        XCTAssertEqual(ArabicTextNormalizer.normalize(input), "الحمد لله اكبر")
    }

    func testTokensIgnorePunctuation() {
        let input = "بِسْمِ ٱللَّهِ، الرَّحْمَـٰنِ"

        XCTAssertEqual(ArabicTextNormalizer.tokens(from: input), ["بسم", "الله", "الرحمن"])
    }
}
