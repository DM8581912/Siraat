import Foundation

/// The canonical "answer key" for an ayah: the expected phoneme sequence with the
/// Tajweed expectations (Madd vowels and their counts/durations) that the engine
/// evaluates a reciter against.
///
/// IMPORTANT (religious correctness): blueprints are *data*, never generated at
/// runtime. They are bundled as verified JSON authored against a cited corpus. The
/// `source.verified` flag gates whether an ayah may drive colored feedback in
/// production — see `BundledPhoneticBlueprintLoader` and the feature gating in the
/// recitation view model. The shipped placeholder (Al-Fatiha only) is `verified:false`.
struct PhoneticBlueprintFile: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let ayahs: [AyahPhonemeMap]
}

struct AyahPhonemeMap: Codable, Equatable, Sendable {
    /// e.g. "1:1".
    let verseKey: String
    /// The exact Uthmani string this map was authored against (for provenance/QA).
    let scriptUthmani: String
    let source: BlueprintProvenance
    /// Canonical phonemes in reading order, one per base letter of the ayah.
    let phonemes: [CanonicalPhoneme]
}

/// Attribution and verification status. `verified == false` means the values are a
/// placeholder and MUST NOT be presented as authoritative Tajweed feedback in production.
struct BlueprintProvenance: Codable, Equatable, Sendable {
    let corpus: String
    let attribution: String
    let verified: Bool
}

struct CanonicalPhoneme: Codable, Equatable, Sendable {
    /// Aligner vocab token (placeholder Buckwalter-ish transliteration for now).
    let symbol: String
    /// The base Arabic letter this phoneme corresponds to.
    let baseLetter: String
    /// Whether this phoneme is a long vowel subject to Madd timing.
    let isMaddVowel: Bool
    /// Expected harakāt count (0, 2, 4, 6). 0 means not a Madd.
    let expectedMaddCount: Int
    /// Canonical duration in seconds at a reference tempo. The evaluator applies a
    /// tolerance ratio rather than comparing exactly.
    let expectedDurationSeconds: Double

    var baseCharacter: Character { baseLetter.first ?? " " }
}
