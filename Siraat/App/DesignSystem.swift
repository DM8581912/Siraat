import CoreText
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
    // Light gold darkened from 0xB8862B (~3.0:1 on white — fails WCAG AA for text) to
    // 0x8A6410 (~4.6:1) so it is legible as a caption/label color on light surfaces.
    // Dark-mode gold stays bright (it sits on a dark surface, contrast is already fine).
    static let gold = Color(lightHex: 0x8A6410, darkHex: 0xE0B65C)
    static let warning = Color(lightHex: 0xC2741E, darkHex: 0xE2944A)
    static let destructive = Color(lightHex: 0xC53330, darkHex: 0xE57470)

    static let textPrimary = Color(lightHex: 0x14201D, darkHex: 0xF2F5F3)
    static let textSecondary = Color(lightHex: 0x5C6864, darkHex: 0x9BA8A3)
}

/// Layout metrics — a small, deliberate radius scale instead of ad-hoc literals scattered
/// per view (the codebase had drifted to 8/12/14/16/18/22). Two tiers cover every surface:
/// `card` for outer containers, `inner` for nested rows/chips.
enum SiraatRadius {
    static let card: CGFloat = 16
    static let inner: CGFloat = 10
}

/// Spacing scale — the single source of truth for padding/gaps. The codebase had drifted to
/// ad-hoc 2/6/8/10/12/14/18/20/22 values; converge on these steps (screens request changes
/// from the coordinator, they do not invent new spacing literals).
enum SiraatSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Type ramp. The app's Latin text rides SwiftUI's semantic styles (so it scales with Dynamic
/// Type for free); these tokens name the rungs so screens stay consistent. Arabic text goes
/// through `ArabicText` (below), which carries its own Dynamic-Type scaling and the Uthmani
/// scripture face. Hierarchy is built from scale + weight contrast, never flat.
enum SiraatType {
    static let display = Font.system(.largeTitle, design: .serif).weight(.bold) // screen title / brand
    static let title = Font.title2.weight(.semibold)                            // card / section heading
    static let heading = Font.headline                                          // row title
    static let body = Font.body                                                 // translation, prose
    static let callout = Font.subheadline                                       // supporting line
    static let caption = Font.caption                                           // metadata
    static let micro = Font.caption2                                            // credits, fine print

    /// Default Arabic display sizes (points at default Dynamic Type), centralized so the
    /// Arabic ramp is consistent. `ArabicText` scales these with the user's text-size setting.
    enum Arabic {
        static let verseOfDay: CGFloat = 24
        static let surahName: CGFloat = 22
        static let name99: CGFloat = 26
        static let dua: CGFloat = 28
        static let dhikr: CGFloat = 34
    }
}

/// Typography assets. The Qur'an verse text wants a real Uthmani face rather than the
/// system serif, which mis-renders some diacritics.
///
/// Drop a licensed Uthmani font (e.g. the SIL OFL "Amiri Quran" or "Scheherazade New",
/// or KFGQPC Uthmanic Script HAFS) into `Siraat/Resources/Fonts/` and set
/// `uthmaniPostScriptName` to its PostScript name. `registerBundledFonts()` loads any
/// bundled .otf/.ttf at launch. Until the asset is present, `Font.quran(...)` falls back
/// to the system font automatically — no crash, just the previous rendering.
enum SiraatFont {
    /// PostScript name of the bundled Uthmani face. Verify with Font Book once the file
    /// is added (it is NOT always the filename).
    static let uthmaniPostScriptName = "AmiriQuran-Regular"

    static func quran(size: CGFloat) -> Font {
        // `relativeTo` makes the custom font scale with Dynamic Type automatically.
        .custom(uthmaniPostScriptName, size: size, relativeTo: .title)
    }

    /// Registers every bundled font file with the process so `Font.custom(...)` can find
    /// it without an Info.plist `UIAppFonts` entry. Call once at app launch. No-op (and
    /// harmless) if no font files are bundled yet.
    static func registerBundledFonts() {
        for ext in ["otf", "ttf"] {
            for url in Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [] {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
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
            .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SiraatRadius.card, style: .continuous)
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

/// Arabic text that scales with Dynamic Type. The app previously hardcoded
/// `.font(.system(size:))` for Arabic, so a low-vision user who enlarged system text got a
/// scaled translation line next to a frozen Arabic line — the exact script they most need
/// enlarged stayed small. `@ScaledMetric` keys the size off the chosen text style so it
/// grows proportionally. Set `scripture: true` for Qur'an verses to use the Uthmani face.
struct ArabicText: View {
    private let text: String
    private let weight: Font.Weight
    private let scripture: Bool
    @ScaledMetric private var size: CGFloat

    init(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        scripture: Bool = false,
        relativeTo style: Font.TextStyle = .title
    ) {
        self.text = text
        self.weight = weight
        self.scripture = scripture
        self._size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    var body: some View {
        let base = Text.arabic(text)
        if scripture {
            base.font(.custom(SiraatFont.uthmaniPostScriptName, size: size))
        } else {
            base.font(.system(size: size, weight: weight))
        }
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
        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SiraatRadius.card, style: .continuous)
                .strokeBorder(SiraatColor.hairline, lineWidth: 1)
        )
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

/// Reusable error boundary: shows a `ContentUnavailableView` with a retry button when
/// an error is present, and the normal content otherwise.
struct ErrorBoundaryView<Content: View>: View {
    let error: String?
    let retryAction: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let error {
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again", action: retryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(SiraatColor.accent)
            }
        } else {
            content()
        }
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
