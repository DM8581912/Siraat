import SwiftUI

enum SiraatColor {
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let accent = Color(red: 0.05, green: 0.47, blue: 0.39)
    static let gold = Color(red: 0.72, green: 0.53, blue: 0.18)
    static let warning = Color(red: 0.82, green: 0.47, blue: 0.12)
    static let destructive = Color(red: 0.78, green: 0.19, blue: 0.18)
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
