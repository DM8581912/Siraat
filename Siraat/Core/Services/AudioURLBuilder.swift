import Foundation

/// Builds per-ayah recitation audio URLs from the everyayah.com CDN, whose layout is
/// deterministic (`{reciterFolder}/{SSSAAA}.mp3`, zero-padded surah+ayah). Deterministic
/// URLs make this trivially unit-testable and enable offline download in a later milestone.
enum AudioURLBuilder {
    /// Maps a reciter id (the `QuranReciter` raw value) to its everyayah folder.
    static func everyAyahFolder(reciterID: Int) -> String? {
        switch reciterID {
        case QuranReciter.misharyAlafasy.rawValue: return "Alafasy_128kbps"
        case QuranReciter.abdulBasit.rawValue: return "Abdul_Basit_Murattal_192kbps"
        case QuranReciter.sudais.rawValue: return "Abdurrahmaan_As-Sudais_192kbps"
        case QuranReciter.saadAlGhamdi.rawValue: return "Ghamadi_40kbps"
        default: return nil
        }
    }

    static func url(reciterID: Int, surah: Int, ayah: Int) -> URL? {
        guard let folder = everyAyahFolder(reciterID: reciterID), surah > 0, ayah > 0 else { return nil }
        let file = String(format: "%03d%03d.mp3", surah, ayah)
        return URL(string: "https://everyayah.com/data/\(folder)/\(file)")
    }
}
