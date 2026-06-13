import CoreText
import SwiftUI
import UIKit

/// The three Tajweed verdict colors plus the neutral text color, resolved to `UIColor`
/// for CoreText. Pulled exclusively from DesignSystem tokens — no color literals here.
struct TajweedPalette {
    let green: UIColor
    let yellow: UIColor
    let red: UIColor
    let neutral: UIColor

    static var standard: TajweedPalette {
        TajweedPalette(
            green: UIColor(SiraatColor.accent),
            yellow: UIColor(SiraatColor.warning),
            red: UIColor(SiraatColor.destructive),
            neutral: UIColor(SiraatColor.textPrimary)
        )
    }

    func color(for verdict: RecitationCharacterColor) -> UIColor {
        switch verdict {
        case .green: green
        case .yellow: yellow
        case .red: red
        }
    }
}

/// Builds a single `NSAttributedString` for an Uthmani ayah with per-cluster foreground
/// colors. Coloring is a per-glyph fill attribute applied over UTF-16 ranges; CoreText
/// still shapes the whole string as one run, so cursive joins, ligatures, and RTL
/// reordering are preserved. (Concatenating separately-colored `Text` runs would break
/// the joins — this does not.) Pure and UIView-free so it can be unit-tested directly.
enum TajweedAttributedStringBuilder {
    static func attributedString(
        uthmani: String,
        results: [RecitationCharacterResult],
        font: UIFont,
        palette: TajweedPalette = .standard
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: uthmani)
        let nsLength = (uthmani as NSString).length
        let fullRange = NSRange(location: 0, length: nsLength)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineHeightMultiple = 1.4

        attributed.addAttributes(
            [
                .font: font,
                .foregroundColor: palette.neutral,
                .paragraphStyle: paragraph,
                // Hint the typesetter that this is Arabic so shaping/marks lay out
                // correctly, mirroring the `.typesettingLanguage("ar")` used elsewhere.
                NSAttributedString.Key(kCTLanguageAttributeName as String): "ar"
            ],
            range: fullRange
        )

        for result in results {
            let location = result.utf16Range.lowerBound
            let length = result.utf16Range.count
            guard length > 0, location >= 0, location + length <= nsLength else { continue }
            attributed.addAttribute(
                .foregroundColor,
                value: palette.color(for: result.color),
                range: NSRange(location: location, length: length)
            )
        }

        return attributed
    }
}
