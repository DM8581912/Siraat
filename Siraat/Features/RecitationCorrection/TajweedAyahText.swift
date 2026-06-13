import CoreText
import SwiftUI
import UIKit

struct TajweedAyahText: View {
    let uthmani: String
    let results: [RecitationCharacterResult]
    @ScaledMetric(relativeTo: .title) private var fontSize: CGFloat = SiraatType.Arabic.dua
    private var font: UIFont {
        UIFont(name: SiraatFont.uthmaniPostScriptName, size: fontSize)
            ?? UIFont.systemFont(ofSize: fontSize)
    }
    private var attributed: NSAttributedString {
        TajweedAttributedStringBuilder.attributedString(
            uthmani: uthmani,
            results: results,
            font: font
        )
    }
    var body: some View {
        CoreTextArabicLabel(attributed: attributed)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(uthmani))
            .accessibilityValue(Text(accessibilitySummary))
    }
    private var accessibilitySummary: String {
        let flagged = results.filter { $0.errorType != nil }
        guard !flagged.isEmpty else { return "Recited correctly" }
        let phrases = flagged.map { result -> String in
            switch result.errorType {
            case .maddShort: "Madd shortened on \(result.char)"
            case .maddLong: "Madd lengthened on \(result.char)"
            case .tashkeelWrong: "Wrong vowel on \(result.char)"
            case .missed: "Missed \(result.char)"
            case .ghunnahMissed: "Missed Ghunnah on \(result.char)"
            case .qalqalahMissed: "Missed Qalqalah on \(result.char)"
            case .makharijWrong: "Makharij mismatch on \(result.char)"
            case .none: ""
            }
        }
        return phrases.joined(separator: ", ")
    }
}

private struct CoreTextArabicLabel: UIViewRepresentable {
    let attributed: NSAttributedString
    func makeUIView(context: Context) -> CoreTextLabelView {
        CoreTextLabelView()
    }
    func updateUIView(_ view: CoreTextLabelView, context: Context) {
        view.attributed = attributed
    }
}

final class CoreTextLabelView: UIView {
    var attributed: NSAttributedString? {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }
    private var lastLaidOutWidth: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func availableWidth() -> CGFloat {
        if bounds.width > 1 { return bounds.width }
        return UIScreen.main.bounds.width - 2 * SiraatSpacing.md
    }
    override var intrinsicContentSize: CGSize {
        guard let attributed else { return .zero }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(width: availableWidth(), height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraint,
            nil
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastLaidOutWidth) > 0.5 {
            lastLaidOutWidth = bounds.width
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let attributed, let context = UIGraphicsGetCurrentContext() else { return }
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: bounds, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }
}
