import Foundation
/// Three-state color verdict for a single rendered Arabic cluster (a base letter
/// together with its diacritics). Green = recited correctly, yellow = a Tajweed
/// duration issue (e.g. a Madd cut short), red = a strict error (missed or a wrong
/// letter/vowel). The renderer maps these to DesignSystem tokens; the values here
/// carry no color literals of their own.
enum RecitationCharacterColor: String, Codable, Equatable, Sendable {
    case green
    case yellow
    case red
}
/// Why a cluster was flagged. `nil` (the error type is absent) means "no error".
/// Raw values match the JSON contract the engine emits.
enum RecitationCharacterErrorType: String, Codable, Equatable, Sendable {
    case maddShort = "madd_short"
    case maddLong = "madd_long"
    case tashkeelWrong = "tashkeel_wrong"
    case missed = "missed"
    case ghunnahMissed = "ghunnah_missed"
    case qalqalahMissed = "qalqalah_missed"
    case makharijWrong = "makharij_wrong"
}
/// Per-character recitation feedback for one Uthmani cluster.
struct RecitationCharacterResult: Equatable, Sendable, Codable {
    let char: String
    let color: RecitationCharacterColor
    let errorType: RecitationCharacterErrorType?
    let duration: TimeInterval
    let utf16Range: Range<Int>
    init(
        char: String,
        color: RecitationCharacterColor,
        errorType: RecitationCharacterErrorType?,
        duration: TimeInterval,
        utf16Range: Range<Int>
    ) {
        self.char = char
        self.color = color
        self.errorType = errorType
        self.duration = duration
        self.utf16Range = utf16Range
    }
    private enum CodingKeys: String, CodingKey {
        case char
        case color
        case errorType = "error_type"
        case duration
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        char = try container.decode(String.self, forKey: .char)
        color = try container.decode(RecitationCharacterColor.self, forKey: .color)
        errorType = try container.decodeIfPresent(RecitationCharacterErrorType.self, forKey: .errorType)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        utf16Range = 0..<0
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(char, forKey: .char)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(errorType, forKey: .errorType)
        try container.encode(duration, forKey: .duration)
    }
}
