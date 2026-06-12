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

    private enum CodingKeys: String, CodingKey {
        case letter
        case confidence
        case duration
        case hasNasalization
        case hasQalqalahBurst
        case articulationClass
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let letterString = try container.decode(String.self, forKey: .letter)
        letter = letterString.first ?? " "
        confidence = try container.decode(Double.self, forKey: .confidence)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        hasNasalization = try container.decode(Bool.self, forKey: .hasNasalization)
        hasQalqalahBurst = try container.decode(Bool.self, forKey: .hasQalqalahBurst)
        articulationClass = try container.decode(String.self, forKey: .articulationClass)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(letter), forKey: .letter)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(duration, forKey: .duration)
        try container.encode(hasNasalization, forKey: .hasNasalization)
        try container.encode(hasQalqalahBurst, forKey: .hasQalqalahBurst)
        try container.encode(articulationClass, forKey: .articulationClass)
    }
}

struct TajweedViolation: Codable, Equatable, Sendable {
    let rule: TajweedRule
    let affectedLetter: Character
    let wordIndex: Int
    let severity: TajweedSeverity
    let confidence: Double
    let userFacingMessage: String

    private enum CodingKeys: String, CodingKey {
        case rule
        case affectedLetter
        case wordIndex
        case severity
        case confidence
        case userFacingMessage
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rule = try container.decode(TajweedRule.self, forKey: .rule)
        let letterString = try container.decode(String.self, forKey: .affectedLetter)
        affectedLetter = letterString.first ?? " "
        wordIndex = try container.decode(Int.self, forKey: .wordIndex)
        severity = try container.decode(TajweedSeverity.self, forKey: .severity)
        confidence = try container.decode(Double.self, forKey: .confidence)
        userFacingMessage = try container.decode(String.self, forKey: .userFacingMessage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rule, forKey: .rule)
        try container.encode(String(affectedLetter), forKey: .affectedLetter)
        try container.encode(wordIndex, forKey: .wordIndex)
        try container.encode(severity, forKey: .severity)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(userFacingMessage, forKey: .userFacingMessage)
    }
}
