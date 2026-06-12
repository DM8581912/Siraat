import Foundation

enum ArabicTextNormalizer {
    private static let diacritics = CharacterSet(charactersIn: "\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0670}\u{06D6}\u{06D7}\u{06D8}\u{06D9}\u{06DA}\u{06DB}\u{06DC}\u{06DF}\u{06E0}\u{06E1}\u{06E2}\u{06E3}\u{06E4}\u{06E7}\u{06E8}\u{06EA}\u{06EB}\u{06EC}\u{06ED}")

    static func normalize(_ text: String) -> String {
        let scalars = text.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard !diacritics.contains(scalar) else { return nil }
            switch scalar {
            case "أ", "إ", "آ", "ٱ":
                return "ا"
            case "ى":
                return "ي"
            case "ؤ":
                return "و"
            case "ئ":
                return "ي"
            case "ة":
                return "ه"
            default:
                return scalar
            }
        }

        return String(String.UnicodeScalarView(scalars))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(from text: String) -> [String] {
        normalize(text)
            .split(separator: " ")
            .map(String.init)
    }
}
