import SwiftUI
import UIKit

private extension Color {
    /// Adaptive color that resolves differently in light vs dark mode. The hand-authored
    /// project has no asset catalog, so colors are defined dynamically in code.
    init(lightHex light: UInt, darkHex dark: UInt) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Calm, reverent palette. Deep teal-green primary with a warm gold accent; warm
/// off-white surfaces in light, deep charcoal (not pure black) in dark. All tokens
/// adapt between light and dark mode.
enum SiraatColor {
    static let background = Color(lightHex: 0xF7F5F0, darkHex: 0x0E1413)
    static let secondaryBackground = Color(lightHex: 0xFFFFFF, darkHex: 0x18211F)
    static let surfaceElevated = Color(lightHex: 0xFFFFFF, darkHex: 0x1F2A27)
    static let hairline = Color(lightHex: 0xE6E1D6, darkHex: 0x2A3633)

    static let accent = Color(lightHex: 0x0C6B57, darkHex: 0x4FC2A6)
    static let accentDeep = Color(lightHex: 0x094B3D, darkHex: 0x2E8C76)
    static let gold = Color(lightHex: 0xB8862B, darkHex: 0xE0B65C)
    static let warning = Color(lightHex: 0xC2741E, darkHex: 0xE2944A)
    static let destructive = Color(lightHex: 0xC53330, darkHex: 0xE57470)

    static let textPrimary = Color(lightHex: 0x14201D, darkHex: 0xF2F5F3)
    static let textSecondary = Color(lightHex: 0x5C6864, darkHex: 0x9BA8A3)
}

/// A reusable elevated surface with consistent corner radius and a soft hairline border.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SiraatColor.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SiraatColor.hairline, lineWidth: 1)
            )
    }
}

extension Text {
    /// Builds Arabic-script text tagged with the Arabic typesetting language. This
    /// gives the text run a language identity so it shapes correctly and VoiceOver
    /// can pronounce it with an Arabic voice instead of the device UI-language voice
    /// (which renders Arabic as unintelligible noise). Returns `Text` so callers can
    /// keep chaining `.font`, `.foregroundStyle`, etc.
    static func arabic(_ string: String) -> Text {
        Text(string).typesettingLanguage(Locale.Language(identifier: "ar"))
    }
}

struct SectionBand<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SiraatColor.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WaveformView: View {
    let level: Double
    let barCount: Int

    init(level: Double, barCount: Int = 18) {
        self.level = level
        self.barCount = barCount
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                let phase = Double(index % 5) / 5
                let height = max(8, 44 * min(1, level + phase * 0.28))
                Capsule()
                    .fill(SiraatColor.accent.gradient)
                    .frame(width: 5, height: height)
                    .animation(.easeInOut(duration: 0.18), value: level)
            }
        }
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio waveform")
        .accessibilityValue(level > 0 ? "Audio detected" : "Silent")
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
