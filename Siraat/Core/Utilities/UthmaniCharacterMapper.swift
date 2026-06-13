import Foundation

/// One render cluster of Uthmani text: a base Arabic letter together with the
/// combining marks (tashkeel, shaddah, Madd marks, dagger alef) that visually attach
/// to it. `utf16Range` are offsets into the source string's UTF-16 view, which is what
/// `NSAttributedString` is indexed by — so the renderer can color a letter and its
/// diacritics as a single unit without breaking Arabic shaping.
struct UthmaniCluster: Equatable {
    let text: String
    /// Normalized base letter (e.g. ٱ→ا). `nil` is never produced here — only base
    /// letters become clusters — but kept optional for forward flexibility.
    let baseLetter: Character?
    let utf16Range: Range<Int>
    /// True if the base is a Madd letter (ا و ي ى) or the cluster carries a Madd mark
    /// (maddah U+0653, dagger alef U+0670).
    let isMaddCluster: Bool
}

/// Segments Uthmani text into base-letter clusters and bridges blueprint phonemes (in
/// reading order) to those clusters. Relies on Swift's grapheme clustering, which
/// already groups an Arabic base letter with its combining marks into one `Character`,
/// and reuses `ArabicLetterInfo` for base-letter classification so the rules here stay
/// in lockstep with the Tajweed engine.
enum UthmaniCharacterMapper {
    /// Ordered base-letter clusters. Spaces, the BOM, and standalone marks are skipped
    /// (they are never colored), but UTF-16 offsets remain correct for those that are.
    static func clusters(in text: String) -> [UthmaniCluster] {
        var clusters: [UthmaniCluster] = []
        var offset = 0

        for character in text {
            let length = String(character).utf16.count
            defer { offset += length }

            guard let base = ArabicLetterInfo.baseLetter(from: character) else { continue }

            let carriesMaddMark = character.unicodeScalars.contains { ArabicLetterInfo.isMaddMark($0) }
            clusters.append(
                UthmaniCluster(
                    text: String(character),
                    baseLetter: base,
                    utf16Range: offset..<(offset + length),
                    isMaddCluster: ArabicLetterInfo.isMaddLetter(base) || carriesMaddMark
                )
            )
        }

        return clusters
    }
}
