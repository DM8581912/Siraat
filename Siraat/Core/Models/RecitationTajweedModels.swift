import Foundation

enum TajweedRule: String, Codable, Equatable, Sendable {
    case ghunnah
    case qalqalah
    case madd
    case makharij

    var displayName: String {
        switch self {
        case .ghunnah: "Ghunnah"
        case .qalqalah: "Qalqalah"
        case .madd: "Madd"
        case .makharij: "Makharij"
        }
    }
}

enum TajweedSeverity: String, Codable, Equatable, Sendable {
    case advisory
    case critical

    var displayName: String {
        switch self {
        case .advisory: "Advisory"
        case .critical: "Needs attention"
        }
    }
}

struct TajweedPhonemeObservation: Codable, Equatable, Sendable {
    let letter: Character
    let confidence: Double
    let duration: TimeInterval
    let hasNasalization: Bool
    let hasQalqalahBurst: Bool
    let articulationClass: String

    init(
        letter: Character,
        confidence: Double,
        duration: TimeInterval,
        hasNasalization: Bool,
        hasQalqalahBurst: Bool,
        articulationClass: String
    ) {
        self.letter = letter
        self.confidence = confidence
        self.duration = duration
        self.hasNasalization = hasNasalization
        self.hasQalqalahBurst = hasQalqalahBurst
        self.articulationClass = articulationClass
    }
}

struct TajweedViolation: Codable, Equatable, Sendable {
    let rule: TajweedRule
    let affectedLetter: Character
    let wordIndex: Int
    let severity: TajweedSeverity
    let confidence: Double
    let userFacingMessage: String

    init(
        rule: TajweedRule,
        affectedLetter: Character,
        wordIndex: Int,
        severity: TajweedSeverity,
        confidence: Double,
        userFacingMessage: String
    ) {
        self.rule = rule
        self.affectedLetter = affectedLetter
        self.wordIndex = wordIndex
        self.severity = severity
        self.confidence = confidence
        self.userFacingMessage = userFacingMessage
    }
}
