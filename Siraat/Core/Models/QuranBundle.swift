import Foundation

/// Decodes the bundled full Quran (Siraat/Resources/FullQuran.json): Uthmani Arabic +
/// Saheeh International English for all 114 surahs / 6236 ayahs, with juz/page/sajda
/// metadata for navigation. This is the offline source of truth for the reader.
struct QuranBundle: Decodable {
    let surahs: [BundledSurah]
}

struct BundledSurah: Decodable, Identifiable, Hashable {
    let number: Int
    let nameArabic: String
    let englishName: String
    let englishNameTranslation: String
    let revelationType: String
    let ayahs: [BundledAyah]

    var id: Int { number }
    var isMeccan: Bool { revelationType.lowercased() == "meccan" }
}

struct BundledAyah: Decodable, Hashable {
    let number: Int           // global 1...6236
    let numberInSurah: Int
    let textUthmani: String
    let textEnglish: String
    let juz: Int
    let page: Int
    let hizbQuarter: Int
    let ruku: Int
    let manzil: Int
    let sajda: Bool

    enum CodingKeys: String, CodingKey {
        case number, numberInSurah, textUthmani, textEnglish, juz, page, hizbQuarter, ruku, manzil, sajda
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        numberInSurah = try c.decode(Int.self, forKey: .numberInSurah)
        textUthmani = try c.decode(String.self, forKey: .textUthmani)
        textEnglish = try c.decodeIfPresent(String.self, forKey: .textEnglish) ?? ""
        juz = try c.decodeIfPresent(Int.self, forKey: .juz) ?? 1
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        hizbQuarter = try c.decodeIfPresent(Int.self, forKey: .hizbQuarter) ?? 1
        ruku = try c.decodeIfPresent(Int.self, forKey: .ruku) ?? 1
        manzil = try c.decodeIfPresent(Int.self, forKey: .manzil) ?? 1
        // Shipped data ships sajda as a plain Bool, so this always decodes. Default the
        // absent/malformed case to false: only 15 of 6236 ayat are sajda, so "not a
        // sajda" is the safe fallback for unknown data.
        sajda = (try? c.decode(Bool.self, forKey: .sajda)) ?? false
    }
}

extension BundledAyah {
    /// Maps into the app's runtime `QuranVerse`. Indo-Pak shares the Uthmani text (the
    /// bundle carries one Arabic script); a dedicated Indo-Pak edition is a later milestone.
    func toQuranVerse(surahNumber: Int, includeEnglish: Bool, audioURL: URL?) -> QuranVerse {
        QuranVerse(
            id: number,
            surahNumber: surahNumber,
            verseNumber: numberInSurah,
            verseKey: "\(surahNumber):\(numberInSurah)",
            textUthmani: textUthmani,
            textIndopak: textUthmani,
            translation: includeEnglish ? textEnglish : "",
            audioURL: audioURL
        )
    }
}
