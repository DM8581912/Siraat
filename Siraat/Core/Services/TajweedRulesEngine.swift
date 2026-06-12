import Foundation

struct TajweedRulesEngine {
    private let criticalConfidenceThreshold = 0.85
    private let minimumMaddDuration: TimeInterval = 0.32
    private let maximumMaddDuration: TimeInterval = 1.30

    func violations(
        expectedWords: [String],
        observations: [Int: [TajweedPhonemeObservation]]
    ) -> [TajweedViolation] {
        expectedWords.enumerated().flatMap { wordIndex, word in
            violations(
                forWord: word,
                wordIndex: wordIndex,
                observations: observations[wordIndex] ?? []
            )
        }
    }

    func violations(
        forWord word: String,
        wordIndex: Int,
        observations: [TajweedPhonemeObservation]
    ) -> [TajweedViolation] {
        let expectedLetters = expectedLetterContexts(in: word)
        var remainingObservations = observations
        var violations: [TajweedViolation] = []

        for context in expectedLetters {
            guard let observation = takeObservation(for: context.baseLetter, from: &remainingObservations) else {
                continue
            }

            if context.requiresGhunnah && !observation.hasNasalization {
                violations.append(
                    violation(
                        rule: .ghunnah,
                        letter: context.baseLetter,
                        wordIndex: wordIndex,
                        confidence: observation.confidence,
                        message: "Possible missed Ghunnah on \(context.baseLetter)"
                    )
                )
            }

            if context.requiresQalqalah && !observation.hasQalqalahBurst {
                violations.append(
                    violation(
                        rule: .qalqalah,
                        letter: context.baseLetter,
                        wordIndex: wordIndex,
                        confidence: observation.confidence,
                        message: "Possible missed Qalqalah on \(context.baseLetter)"
                    )
                )
            }

            if context.requiresMadd && (observation.duration < minimumMaddDuration || observation.duration > maximumMaddDuration) {
                let direction = observation.duration < minimumMaddDuration ? "too short" : "too long"
                violations.append(
                    violation(
                        rule: .madd,
                        letter: context.baseLetter,
                        wordIndex: wordIndex,
                        confidence: observation.confidence,
                        message: "Madd may be \(direction) on \(context.baseLetter)"
                    )
                )
            }

            if
                let expectedArticulation = ArabicLetterInfo.articulationClass(for: context.baseLetter),
                !observation.articulationClass.isEmpty,
                observation.articulationClass != "unknown",
                observation.articulationClass != expectedArticulation
            {
                violations.append(
                    violation(
                        rule: .makharij,
                        letter: context.baseLetter,
                        wordIndex: wordIndex,
                        confidence: observation.confidence,
                        message: "Possible Makharij mismatch on \(context.baseLetter)"
                    )
                )
            }
        }

        return violations
    }

    private func violation(
        rule: TajweedRule,
        letter: Character,
        wordIndex: Int,
        confidence: Double,
        message: String
    ) -> TajweedViolation {
        TajweedViolation(
            rule: rule,
            affectedLetter: letter,
            wordIndex: wordIndex,
            severity: confidence >= criticalConfidenceThreshold ? .critical : .advisory,
            confidence: confidence,
            userFacingMessage: message
        )
    }

    private func takeObservation(
        for expectedLetter: Character,
        from observations: inout [TajweedPhonemeObservation]
    ) -> TajweedPhonemeObservation? {
        guard let index = observations.firstIndex(where: { ArabicLetterInfo.sameBaseLetter($0.letter, expectedLetter) }) else {
            return nil
        }

        return observations.remove(at: index)
    }

    private func expectedLetterContexts(in word: String) -> [ExpectedLetterContext] {
        let characters = Array(word)
        let baseLetterIndices = characters.indices.filter { ArabicLetterInfo.baseLetter(from: characters[$0]) != nil }

        return baseLetterIndices.compactMap { index in
            guard let baseLetter = ArabicLetterInfo.baseLetter(from: characters[index]) else { return nil }

            let scalarSet = Set(characters[index].unicodeScalars.map(\.value))
            let isFinalBaseLetter = index == baseLetterIndices.last
            let hasTrailingMaddMarker = characters.dropFirst(index + 1).prefix { ArabicLetterInfo.baseLetter(from: $0) == nil }.contains {
                $0.unicodeScalars.contains { ArabicLetterInfo.isMaddMark($0) }
            }

            return ExpectedLetterContext(
                baseLetter: baseLetter,
                requiresGhunnah: ArabicLetterInfo.requiresGhunnah(baseLetter: baseLetter, scalars: scalarSet),
                requiresQalqalah: ArabicLetterInfo.isQalqalahLetter(baseLetter) && (scalarSet.contains(ArabicLetterInfo.sukun) || isFinalBaseLetter),
                requiresMadd: ArabicLetterInfo.isMaddLetter(baseLetter) || hasTrailingMaddMarker
            )
        }
    }
}

private struct ExpectedLetterContext {
    let baseLetter: Character
    let requiresGhunnah: Bool
    let requiresQalqalah: Bool
    let requiresMadd: Bool
}

enum ArabicLetterInfo {
    static let sukun: UInt32 = 0x0652

    private static let shaddah: UInt32 = 0x0651
    private static let tanweenScalars: Set<UInt32> = [0x064B, 0x064C, 0x064D]
    private static let maddScalars: Set<UInt32> = [0x0653, 0x0670]
    private static let qalqalahLetters: Set<Character> = ["ق", "ط", "ب", "ج", "د"]
    private static let maddLetters: Set<Character> = ["ا", "و", "ي", "ى", "آ"]

    private static let articulationProfiles: [Character: String] = [
        "ء": "throat", "ا": "throat", "أ": "throat", "إ": "throat", "آ": "throat", "ه": "throat", "ع": "throat", "ح": "throat", "غ": "throat", "خ": "throat",
        "ق": "tongue-back", "ك": "tongue-back",
        "ج": "tongue-mid", "ش": "tongue-mid", "ي": "tongue-mid", "ى": "tongue-mid",
        "ض": "tongue-side", "ل": "tongue-side",
        "ن": "tongue-front", "ر": "tongue-front", "ت": "tongue-front", "د": "tongue-front", "ط": "tongue-front", "ث": "tongue-front", "ذ": "tongue-front", "ظ": "tongue-front", "س": "tongue-front", "ز": "tongue-front", "ص": "tongue-front",
        "ف": "lips", "ب": "lips", "م": "lips", "و": "lips"
    ]

    static func baseLetter(from character: Character) -> Character? {
        for scalar in character.unicodeScalars where isArabicLetter(scalar) {
            return normalizedBaseLetter(Character(String(scalar)))
        }

        return nil
    }

    static func sameBaseLetter(_ lhs: Character, _ rhs: Character) -> Bool {
        normalizedBaseLetter(lhs) == normalizedBaseLetter(rhs)
    }

    static func isQalqalahLetter(_ letter: Character) -> Bool {
        qalqalahLetters.contains(normalizedBaseLetter(letter))
    }

    static func isMaddLetter(_ letter: Character) -> Bool {
        maddLetters.contains(normalizedBaseLetter(letter))
    }

    static func isMaddMark(_ scalar: UnicodeScalar) -> Bool {
        maddScalars.contains(scalar.value)
    }

    static func articulationClass(for letter: Character) -> String? {
        articulationProfiles[normalizedBaseLetter(letter)]
    }

    static func requiresGhunnah(baseLetter: Character, scalars: Set<UInt32>) -> Bool {
        let normalized = normalizedBaseLetter(baseLetter)
        return ((normalized == "ن" || normalized == "م") && scalars.contains(shaddah)) ||
            !tanweenScalars.isDisjoint(with: scalars)
    }

    private static func normalizedBaseLetter(_ letter: Character) -> Character {
        switch letter {
        case "ٱ", "أ", "إ": "ا"
        case "ى": "ي"
        default: letter
        }
    }

    private static func isArabicLetter(_ scalar: UnicodeScalar) -> Bool {
        (0x0621...0x064A).contains(scalar.value) || scalar.value == 0x0671
    }
}
