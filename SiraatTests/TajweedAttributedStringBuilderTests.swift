import XCTest
import UIKit
@testable import Siraat

final class TajweedAttributedStringBuilderTests: XCTestCase {
    private let palette = TajweedPalette(
        green: .green,
        yellow: .yellow,
        red: .red,
        neutral: .label
    )

    func testAppliesPerClusterForegroundColor() {
        let uthmani = "بَا"
        let length = (uthmani as NSString).length
        let results = [
            RecitationCharacterResult(char: "بَ", color: .red, errorType: .tashkeelWrong, duration: 0.1, utf16Range: 0..<2),
            RecitationCharacterResult(char: "ا", color: .yellow, errorType: .maddShort, duration: 0.3, utf16Range: 2..<length)
        ]

        let attributed = TajweedAttributedStringBuilder.attributedString(
            uthmani: uthmani,
            results: results,
            font: .systemFont(ofSize: 28),
            palette: palette
        )

        let firstColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        let lastColor = attributed.attribute(.foregroundColor, at: length - 1, effectiveRange: nil) as? UIColor
        XCTAssertEqual(firstColor, .red)
        XCTAssertEqual(lastColor, .yellow)
    }

    func testUncoloredRegionsKeepNeutralColor() {
        let uthmani = "ا ب"
        let results = [
            RecitationCharacterResult(char: "ا", color: .green, errorType: nil, duration: 0.1, utf16Range: 0..<1)
        ]
        let attributed = TajweedAttributedStringBuilder.attributedString(
            uthmani: uthmani,
            results: results,
            font: .systemFont(ofSize: 28),
            palette: palette
        )
        // The space (offset 1) and ب (offset 2) were not colored → neutral.
        let spaceColor = attributed.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor
        XCTAssertEqual(spaceColor, .label)
    }

    func testOutOfBoundsRangeIsIgnored() {
        let uthmani = "ب"
        let results = [
            RecitationCharacterResult(char: "ب", color: .red, errorType: .missed, duration: 0, utf16Range: 5..<9)
        ]
        // Should not crash; the out-of-range result is skipped.
        let attributed = TajweedAttributedStringBuilder.attributedString(
            uthmani: uthmani,
            results: results,
            font: .systemFont(ofSize: 28),
            palette: palette
        )
        XCTAssertEqual(attributed.string, uthmani)
    }
}
