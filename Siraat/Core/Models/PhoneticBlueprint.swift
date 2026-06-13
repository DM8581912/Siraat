import Foundation

struct PhoneticBlueprintFile: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let ayahs: [AyahPhonemeMap]
}

struct AyahPhonemeMap: Codable, Equatable, Sendable {
    let verseKey: String
    let scriptUthmani: String
    let source: BlueprintProvenance
    let phonemes: [CanonicalPhoneme]
}

struct BlueprintProvenance: Codable, Equatable, Sendable {
    let corpus: String
    let attribution: String
    let verified: Bool
}

struct CanonicalPhoneme: Codable, Equatable, Sendable {
    let symbol: String
    let baseLetter: String
    let isMaddVowel: Bool
    let expectedMaddCount: Int
    let expectedDurationSeconds: Double
    let requiresGhunnah: Bool
    let requiresQalqalah: Bool

    var baseCharacter: Character { baseLetter.first ?? " " }

    init(
        symbol: String,
        baseLetter: String,
        isMaddVowel: Bool,
        expectedMaddCount: Int,
        expectedDurationSeconds: Double,
        requiresGhunnah: Bool = false,
        requiresQalqalah: Bool = false
    ) {
        self.symbol = symbol
        self.baseLetter = baseLetter
        self.isMaddVowel = isMaddVowel
        self.expectedMaddCount = expectedMaddCount
        self.expectedDurationSeconds = expectedDurationSeconds
        self.requiresGhunnah = requiresGhunnah
        self.requiresQalqalah = requiresQalqalah
    }

    // Tolerant decoding: the Ghunnah/Qalqalah flags were added after the first blueprints
    // were authored, so default them to false when an older JSON omits them. This keeps the
    // placeholder Al-Fatiha blueprint (and any pre-existing data) loadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        baseLetter = try container.decode(String.self, forKey: .baseLetter)
        isMaddVowel = try container.decode(Bool.self, forKey: .isMaddVowel)
        expectedMaddCount = try container.decode(Int.self, forKey: .expectedMaddCount)
        expectedDurationSeconds = try container.decode(Double.self, forKey: .expectedDurationSeconds)
        requiresGhunnah = try container.decodeIfPresent(Bool.self, forKey: .requiresGhunnah) ?? false
        requiresQalqalah = try container.decodeIfPresent(Bool.self, forKey: .requiresQalqalah) ?? false
    }
}
