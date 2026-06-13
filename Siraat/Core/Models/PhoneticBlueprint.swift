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
}
