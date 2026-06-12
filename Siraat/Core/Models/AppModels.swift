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
        case .urdu: 97
        case .turkish: 77
        case .indonesian: 33
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

    static let `default` = ReaderSettings(
        script: .uthmani,
        readingMode: .continuous,
        fontSize: 28,
        translationLanguage: .english,
        selectedReciterID: QuranReciter.misharyAlafasy.rawValue,
        appearanceMode: .system
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
