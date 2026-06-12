import Foundation

/// A loaded page of verses plus the credit for the translation that is ACTUALLY shown.
/// `translationCredit` and `isOfflineEnglishFallback` exist so the reader never displays
/// text under the wrong translator's name (e.g. English under an Urdu credit when offline).
struct QuranVersePage {
    let verses: [QuranVerse]
    let translationCredit: String
    let isOfflineEnglishFallback: Bool
}

protocol QuranDatabaseManaging {
    func verses(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) async throws -> [QuranVerse]
    func versePage(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) async throws -> QuranVersePage
    func surahMetadata() async -> [BundledSurah]
    func ayahs(inJuz juz: Int, language: TranslationLanguage, reciterID: Int) async -> [QuranVerse]
    func ayah(surah: Int, ayah: Int) async -> QuranVerse?
    func verse(globalNumber: Int) async -> QuranVerse?
    func cachedBookmarks() async -> [Bookmark]
    func saveBookmarks(_ bookmarks: [Bookmark]) async
    func readingPosition() async -> QuranReadingPosition?
    func saveReadingPosition(_ position: QuranReadingPosition) async
    func readerSettings() async -> ReaderSettings
    func saveReaderSettings(_ settings: ReaderSettings) async
}

extension QuranDatabaseManaging {
    /// Default for conformers (e.g. test mocks) that only implement `verses`: assume the
    /// requested language's translation is what was shown. The real `QuranDatabaseManager`
    /// overrides this with offline-edition handling and a misattribution-safe fallback.
    func versePage(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) async throws -> QuranVersePage {
        let verses = try await verses(forSurah: surah, language: language, reciterID: reciterID)
        return QuranVersePage(verses: verses, translationCredit: language.quranTranslationCredit, isOfflineEnglishFallback: false)
    }
}

enum QuranDatabaseError: LocalizedError {
    case invalidURL
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The Quran API URL is invalid."
        case .emptyResponse: "No verses were available."
        }
    }
}

actor QuranDatabaseManager: QuranDatabaseManaging {
    private let session: URLSession
    private let secretsProvider: SecretsProviding
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let userDefaults: UserDefaults

    // Lazily-parsed bundled full Quran (offline source of truth). Nil if the resource is
    // missing/corrupt, in which case the manager falls back to the online path + sample.
    private var bundleLoaded = false
    private var surahLookup: [Int: BundledSurah] = [:]
    private var orderedSurahs: [BundledSurah] = []
    // Lazily-parsed offline translation editions, keyed by language (global ayah # → text).
    private var translationLookups: [TranslationLanguage: [Int: String]] = [:]

    init(
        session: URLSession = .shared,
        secretsProvider: SecretsProviding = SecretsProvider(),
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        userDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.secretsProvider = secretsProvider
        self.decoder = decoder
        self.encoder = encoder
        self.userDefaults = userDefaults
    }

    func verses(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) async throws -> [QuranVerse] {
        try await versePage(forSurah: surah, language: language, reciterID: reciterID).verses
    }

    func versePage(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) async throws -> QuranVersePage {
        // English and the bundled non-English editions (ur/id/tr) ship fully offline —
        // instant, no network, correct attribution.
        if let verses = bundleVerses(forSurah: surah, language: language, reciterID: reciterID) {
            return QuranVersePage(verses: verses, translationCredit: language.quranTranslationCredit, isOfflineEnglishFallback: false)
        }

        if let cached = cachedVerses(forSurah: surah, language: language, reciterID: reciterID), !cached.isEmpty {
            return QuranVersePage(verses: cached, translationCredit: language.quranTranslationCredit, isOfflineEnglishFallback: false)
        }

        do {
            let remote = try await fetchRemoteVerses(forSurah: surah, language: language, reciterID: reciterID)
            saveCachedVerses(remote, surah: surah, language: language, reciterID: reciterID)
            return QuranVersePage(verses: remote, translationCredit: language.quranTranslationCredit, isOfflineEnglishFallback: false)
        } catch {
            // Offline and no edition/cache for this language (es/fr). Show English so the
            // screen is never blank, but attribute it HONESTLY to Saheeh International and
            // flag the fallback — never English text under, say, the French credit.
            if let verses = bundleVerses(forSurah: surah, language: .english, reciterID: reciterID) {
                return QuranVersePage(
                    verses: verses,
                    translationCredit: TranslationLanguage.english.quranTranslationCredit,
                    isOfflineEnglishFallback: true
                )
            }
            let fallback = try loadSampleVerses()
            guard !fallback.isEmpty else { throw error }
            return QuranVersePage(
                verses: fallback,
                translationCredit: TranslationLanguage.english.quranTranslationCredit,
                isOfflineEnglishFallback: true
            )
        }
    }

    func surahMetadata() async -> [BundledSurah] {
        loadBundleIfNeeded()
        return orderedSurahs
    }

    func ayahs(inJuz juz: Int, language: TranslationLanguage, reciterID: Int) async -> [QuranVerse] {
        loadBundleIfNeeded()
        var result: [QuranVerse] = []
        for surah in orderedSurahs {
            for ayah in surah.ayahs where ayah.juz == juz {
                result.append(ayah.toQuranVerse(
                    surahNumber: surah.number,
                    includeEnglish: language == .english,
                    audioURL: AudioURLBuilder.url(reciterID: reciterID, surah: surah.number, ayah: ayah.numberInSurah)
                ))
            }
        }
        return result
    }

    func ayah(surah: Int, ayah: Int) async -> QuranVerse? {
        loadBundleIfNeeded()
        guard let bundledSurah = surahLookup[surah],
              let bundledAyah = bundledSurah.ayahs.first(where: { $0.numberInSurah == ayah })
        else { return nil }
        return bundledAyah.toQuranVerse(surahNumber: surah, includeEnglish: true, audioURL: nil)
    }

    func verse(globalNumber: Int) async -> QuranVerse? {
        loadBundleIfNeeded()
        for surah in orderedSurahs {
            if let bundledAyah = surah.ayahs.first(where: { $0.number == globalNumber }) {
                return bundledAyah.toQuranVerse(surahNumber: surah.number, includeEnglish: true, audioURL: nil)
            }
        }
        return nil
    }

    private func loadBundleIfNeeded() {
        guard !bundleLoaded else { return }
        bundleLoaded = true
        guard
            let url = Bundle.main.url(forResource: "FullQuran", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let bundle = try? decoder.decode(QuranBundle.self, from: data)
        else { return }
        orderedSurahs = bundle.surahs
        surahLookup = Dictionary(uniqueKeysWithValues: bundle.surahs.map { ($0.number, $0) })
    }

    /// Builds a surah's verses entirely from bundled assets, or nil when no offline edition
    /// covers `language`. English text lives inside FullQuran.json; other languages load a
    /// side-car `Translation-<code>.json` and overlay it on the bundle's Arabic.
    private func bundleVerses(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) -> [QuranVerse]? {
        loadBundleIfNeeded()
        guard let bundledSurah = surahLookup[surah], !bundledSurah.ayahs.isEmpty else { return nil }

        let translationLookup: [Int: String]
        if language == .english {
            translationLookup = [:]   // use each ayah's bundled English text
        } else if let lookup = bundledTranslationLookup(for: language) {
            translationLookup = lookup
        } else {
            return nil                // no bundled edition for this language
        }

        return bundledSurah.ayahs.map { ayah in
            ayah.toQuranVerse(
                surahNumber: surah,
                includeEnglish: language == .english,
                audioURL: AudioURLBuilder.url(reciterID: reciterID, surah: surah, ayah: ayah.numberInSurah),
                translationOverride: language == .english ? nil : (translationLookup[ayah.number] ?? "")
            )
        }
    }

    /// Loads and caches a bundled translation edition as a global-ayah-number → text map.
    /// `texts[i]` is ayah `i + 1` (mushaf order); see Scripts/build_translations.py.
    private func bundledTranslationLookup(for language: TranslationLanguage) -> [Int: String]? {
        if let cached = translationLookups[language] { return cached }
        guard
            let url = Bundle.main.url(forResource: "Translation-\(language.rawValue)", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let edition = try? decoder.decode(BundledTranslation.self, from: data),
            edition.texts.count == Self.totalAyahCount
        else {
            return nil
        }
        var lookup = [Int: String](minimumCapacity: edition.texts.count)
        for (index, text) in edition.texts.enumerated() {
            lookup[index + 1] = text
        }
        translationLookups[language] = lookup
        return lookup
    }

    private static let totalAyahCount = 6236

    func cachedBookmarks() async -> [Bookmark] {
        guard let data = userDefaults.data(forKey: StorageKey.bookmarks.rawValue),
              let bookmarks = try? decoder.decode([Bookmark].self, from: data) else {
            return []
        }

        return bookmarks
    }

    func saveBookmarks(_ bookmarks: [Bookmark]) async {
        guard let data = try? encoder.encode(bookmarks) else { return }
        userDefaults.set(data, forKey: StorageKey.bookmarks.rawValue)
    }

    func readingPosition() async -> QuranReadingPosition? {
        guard let data = userDefaults.data(forKey: StorageKey.readingPosition.rawValue) else {
            return nil
        }

        return try? decoder.decode(QuranReadingPosition.self, from: data)
    }

    func saveReadingPosition(_ position: QuranReadingPosition) async {
        guard let data = try? encoder.encode(position) else { return }
        userDefaults.set(data, forKey: StorageKey.readingPosition.rawValue)
    }

    func readerSettings() async -> ReaderSettings {
        guard let data = userDefaults.data(forKey: StorageKey.readerSettings.rawValue),
              let settings = try? decoder.decode(ReaderSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    func saveReaderSettings(_ settings: ReaderSettings) async {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: StorageKey.readerSettings.rawValue)
    }

    private func fetchRemoteVerses(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) async throws -> [QuranVerse] {
        let base = secretsProvider.value(for: .quranContentAPIBaseURL) ?? "https://api.quran.com/api/v4"
        guard var components = URLComponents(string: "\(base)/verses/by_chapter/\(surah)") else {
            throw QuranDatabaseError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "language", value: language.rawValue),
            URLQueryItem(name: "words", value: "false"),
            URLQueryItem(name: "translations", value: "\(language.quranTranslationResourceID)"),
            URLQueryItem(name: "audio", value: "\(reciterID)"),
            URLQueryItem(name: "fields", value: "text_uthmani,text_indopak,verse_key"),
            URLQueryItem(name: "per_page", value: "286")
        ]

        guard let url = components.url else {
            throw QuranDatabaseError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let response = try decoder.decode(QuranVersesResponse.self, from: data)
        let verses = response.verses.map { $0.toModel(surahNumber: surah) }
        guard !verses.isEmpty else {
            throw QuranDatabaseError.emptyResponse
        }

        return verses
    }

    private func loadSampleVerses() throws -> [QuranVerse] {
        guard let url = Bundle.main.url(forResource: "SampleQuran", withExtension: "json") else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([QuranVerse].self, from: data)
    }

    private func cachedVerses(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) -> [QuranVerse]? {
        guard let data = userDefaults.data(forKey: cacheKey(surah: surah, language: language, reciterID: reciterID)) else {
            return nil
        }

        return try? decoder.decode([QuranVerse].self, from: data)
    }

    private func saveCachedVerses(_ verses: [QuranVerse], surah: Int, language: TranslationLanguage, reciterID: Int) {
        guard let data = try? encoder.encode(verses) else { return }
        userDefaults.set(data, forKey: cacheKey(surah: surah, language: language, reciterID: reciterID))
    }

    private func cacheKey(surah: Int, language: TranslationLanguage, reciterID: Int) -> String {
        "quran.verses.\(surah).\(language.rawValue).\(reciterID)"
    }
}

private enum StorageKey: String {
    case bookmarks = "bookmarks"
    case readingPosition = "readingPosition"
    case readerSettings = "readerSettings"
}

/// A bundled offline translation edition (Resources/Translations/Translation-<code>.json),
/// produced by Scripts/build_translations.py. `texts` is mushaf-ordered: index i = ayah i+1.
private struct BundledTranslation: Decodable {
    let language: String
    let resourceId: Int
    let credit: String
    let texts: [String]
}

private struct QuranVersesResponse: Decodable {
    let verses: [QuranVerseDTO]
}

private struct QuranVerseDTO: Decodable {
    let id: Int
    let verseNumber: Int
    let verseKey: String
    let textUthmani: String?
    let textIndopak: String?
    let translations: [QuranTranslationDTO]?
    let audio: QuranAudioDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case verseNumber = "verse_number"
        case verseKey = "verse_key"
        case textUthmani = "text_uthmani"
        case textIndopak = "text_indopak"
        case translations
        case audio
    }

    func toModel(surahNumber: Int) -> QuranVerse {
        QuranVerse(
            id: id,
            surahNumber: surahNumber,
            verseNumber: verseNumber,
            verseKey: verseKey,
            textUthmani: textUthmani ?? "",
            textIndopak: textIndopak ?? textUthmani ?? "",
            translation: translations?.first?.text.strippingHTML ?? "",
            audioURL: audio?.url
        )
    }
}

private struct QuranTranslationDTO: Decodable {
    let text: String
}

private struct QuranAudioDTO: Decodable {
    let url: URL?

    enum CodingKeys: String, CodingKey {
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawURL = try container.decodeIfPresent(String.self, forKey: .url)
        url = Self.normalizedAudioURL(from: rawURL)
    }

    private static func normalizedAudioURL(from rawURL: String?) -> URL? {
        guard let rawURL, !rawURL.isEmpty else { return nil }

        if rawURL.hasPrefix("http") {
            return URL(string: rawURL)
        }

        if rawURL.hasPrefix("//") {
            return URL(string: "https:\(rawURL)")
        }

        if rawURL.hasPrefix("/") {
            return URL(string: "https://verses.quran.com\(rawURL)")
        }

        return URL(string: "https://verses.quran.com/\(rawURL)")
    }
}

private extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
