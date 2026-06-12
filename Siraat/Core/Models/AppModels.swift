import Foundation

enum TranslationLanguage: String, CaseIterable, Identifiable, Codable, Hashable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case urdu = "ur"
    case turkish = "tr"
    case indonesian = "id"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .urdu: "Urdu"
        case .turkish: "Turkish"
        case .indonesian: "Indonesian"
        }
    }

    var quranTranslationResourceID: Int {
        switch self {
        case .english: 131
        case .spanish: 83
        case .french: 31
        // Urdu uses Jalandhari (public domain) rather than Maududi/Tafheem (copyrighted)
        // so the edition can be bundled offline and shipped without a licensing question.
        case .urdu: 234
        case .turkish: 77
        case .indonesian: 33
        }
    }

    /// True when a full offline edition for this language ships in the app bundle
    /// (`Resources/Translations/Translation-<code>.json`, built by Scripts/build_translations.py).
    var hasBundledEdition: Bool {
        switch self {
        case .urdu, .turkish, .indonesian: true
        case .english: true   // English ships inside FullQuran.json
        case .spanish, .french: false
        }
    }

    /// Translator credit for the quran.com edition above. Quran translations are
    /// established, attributed works and must be credited in-app — never presented as
    /// app-generated.
    var quranTranslationCredit: String {
        switch self {
        case .english: "Saheeh International"
        case .spanish: "Sheikh Isa García"
        case .french: "Muhammad Hamidullah"
        case .urdu: "Fatah Muhammad Jalandhari"
        case .turkish: "Diyanet İşleri"
        case .indonesian: "Kementerian Agama Republik Indonesia"
        }
    }
}

enum QuranReciter: Int, CaseIterable, Identifiable, Codable, Hashable {
    case misharyAlafasy = 7
    case abdulBasit = 1
    case sudais = 3
    case saadAlGhamdi = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .misharyAlafasy: "Mishary Alafasy"
        case .abdulBasit: "Abdul Basit"
        case .sudais: "Abdur-Rahman as-Sudais"
        case .saadAlGhamdi: "Saad al-Ghamdi"
        }
    }
}

enum QuranScript: String, CaseIterable, Identifiable, Codable, Hashable {
    case uthmani
    case indopak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uthmani: "Uthmani"
        case .indopak: "Indo-Pak"
        }
    }
}

enum ReadingMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case continuous
    case page

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .continuous: "Scroll"
        case .page: "Page"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct QuranVerse: Identifiable, Codable, Hashable {
    let id: Int
    let surahNumber: Int
    let verseNumber: Int
    let verseKey: String
    let textUthmani: String
    let textIndopak: String
    let translation: String
    let audioURL: URL?

    func text(for script: QuranScript) -> String {
        switch script {
        case .uthmani: textUthmani
        case .indopak: textIndopak
        }
    }
}

struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let verseKey: String
    let note: String?
    let createdAt: Date

    init(id: UUID = UUID(), verseKey: String, note: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.verseKey = verseKey
        self.note = note
        self.createdAt = createdAt
    }
}

struct QuranReadingPosition: Codable, Equatable {
    let surahNumber: Int
    let verseNumber: Int
    let verseKey: String
    let updatedAt: Date

    init(surahNumber: Int, verseNumber: Int, verseKey: String, updatedAt: Date = Date()) {
        self.surahNumber = surahNumber
        self.verseNumber = verseNumber
        self.verseKey = verseKey
        self.updatedAt = updatedAt
    }
}

struct ReaderSettings: Codable, Equatable {
    var script: QuranScript
    var readingMode: ReadingMode
    var fontSize: Double
    var translationLanguage: TranslationLanguage
    var selectedReciterID: Int
    var appearanceMode: AppearanceMode
    var calculationMethod: CalculationMethod
    var madhab: Madhab
    /// nil = let Adhan pick the recommended high-latitude rule automatically.
    var highLatitudeRule: HighLatitudeRule?
    /// Manual ±days nudge for the Hijri date to match local moon-sighting (-2...2).
    var hijriDayAdjustment: Int
    /// Per-prayer minute adjustments so users can match their local mosque's timetable.
    /// Backed by the Adhan library's PrayerAdjustments (applied after the engine computes
    /// times). Positive = later, negative = earlier. Clamped to -30...30 in the UI.
    var prayerAdjustments: PrayerAdjustments

    init(
        script: QuranScript,
        readingMode: ReadingMode,
        fontSize: Double,
        translationLanguage: TranslationLanguage,
        selectedReciterID: Int,
        appearanceMode: AppearanceMode,
        calculationMethod: CalculationMethod = .muslimWorldLeague,
        madhab: Madhab = .shafi,
        highLatitudeRule: HighLatitudeRule? = nil,
        hijriDayAdjustment: Int = 0,
        prayerAdjustments: PrayerAdjustments = PrayerAdjustments()
    ) {
        self.script = script
        self.readingMode = readingMode
        self.fontSize = fontSize
        self.translationLanguage = translationLanguage
        self.selectedReciterID = selectedReciterID
        self.appearanceMode = appearanceMode
        self.calculationMethod = calculationMethod
        self.madhab = madhab
        self.highLatitudeRule = highLatitudeRule
        self.hijriDayAdjustment = hijriDayAdjustment
        self.prayerAdjustments = prayerAdjustments
    }

    // Decode defensively: prayer-calculation fields were added later, so settings
    // persisted by older builds won't contain them. decodeIfPresent preserves the
    // user's other reader preferences instead of failing the whole decode. New users
    // get a region-appropriate calculation method instead of MWL-for-everyone.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        script = try container.decode(QuranScript.self, forKey: .script)
        readingMode = try container.decode(ReadingMode.self, forKey: .readingMode)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        translationLanguage = try container.decode(TranslationLanguage.self, forKey: .translationLanguage)
        selectedReciterID = try container.decode(Int.self, forKey: .selectedReciterID)
        appearanceMode = try container.decode(AppearanceMode.self, forKey: .appearanceMode)
        calculationMethod = try container.decodeIfPresent(CalculationMethod.self, forKey: .calculationMethod) ?? .regionalDefault()
        madhab = try container.decodeIfPresent(Madhab.self, forKey: .madhab) ?? .shafi
        highLatitudeRule = try container.decodeIfPresent(HighLatitudeRule.self, forKey: .highLatitudeRule)
        hijriDayAdjustment = try container.decodeIfPresent(Int.self, forKey: .hijriDayAdjustment) ?? 0
        prayerAdjustments = try container.decodeIfPresent(PrayerAdjustments.self, forKey: .prayerAdjustments) ?? PrayerAdjustments()
    }

    static let `default` = ReaderSettings(
        script: .uthmani,
        readingMode: .continuous,
        fontSize: 28,
        translationLanguage: .english,
        selectedReciterID: QuranReciter.misharyAlafasy.rawValue,
        appearanceMode: .system,
        calculationMethod: .regionalDefault(),
        madhab: .shafi,
        highLatitudeRule: nil,
        hijriDayAdjustment: 0,
        prayerAdjustments: PrayerAdjustments()
    )
}

struct SpeechTranscriptSegment: Identifiable, Equatable {
    let id: UUID
    let text: String
    let isFinal: Bool
    let createdAt: Date

    init(id: UUID = UUID(), text: String, isFinal: Bool, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.createdAt = createdAt
    }
}

struct TranslationSegment: Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let targetLanguage: TranslationLanguage
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        targetLanguage: TranslationLanguage,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
    }
}

enum RecitationWordStatus: String, Codable, Equatable {
    case pending
    case correct
    case uncertain
    case missed
}

struct CorrectionTip: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let message: String

    init(id: UUID = UUID(), title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

struct RecitationWord: Identifiable, Codable, Equatable {
    let id: UUID
    let originalText: String
    var status: RecitationWordStatus
    var tip: CorrectionTip?

    init(id: UUID = UUID(), originalText: String, status: RecitationWordStatus = .pending, tip: CorrectionTip? = nil) {
        self.id = id
        self.originalText = originalText
        self.status = status
        self.tip = tip
    }
}
