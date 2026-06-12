import Foundation

protocol QuranDatabaseManaging {
    func verses(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) async throws -> [QuranVerse]
    func surahMetadata() async -> [BundledSurah]
    func ayahs(inJuz juz: Int, language: TranslationLanguage, reciterID: Int) async -> [QuranVerse]
    func ayah(surah: Int, ayah: Int) async -> QuranVerse?
    func cachedBookmarks() async -> [Bookmark]
    func saveBookmarks(_ bookmarks: [Bookmark]) async
    func readingPosition() async -> QuranReadingPosition?
    func saveReadingPosition(_ position: QuranReadingPosition) async
    func readerSettings() async -> ReaderSettings
    func saveReaderSettings(_ settings: ReaderSettings) async
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
        // English ships fully offline in the bundle — instant, no network.
        if language == .english, let verses = bundleVerses(forSurah: surah, includeEnglish: true, reciterID: reciterID) {
            return verses
        }

        if let cached = cachedVerses(forSurah: surah, language: language, reciterID: reciterID), !cached.isEmpty {
            return cached
        }

        do {
            let remote = try await fetchRemoteVerses(forSurah: surah, language: language, reciterID: reciterID)
            saveCachedVerses(remote, surah: surah, language: language, reciterID: reciterID)
            return remote
        } catch {
            // Offline fallback: bundle Arabic + English so the screen is never blank.
            if let verses = bundleVerses(forSurah: surah, includeEnglish: true, reciterID: reciterID) {
                return verses
            }
            let fallback = try loadSampleVerses()
            guard !fallback.isEmpty else { throw error }
            return fallback
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

    private func bundleVerses(forSurah surah: Int, includeEnglish: Bool, reciterID: Int) -> [QuranVerse]? {
        loadBundleIfNeeded()
        guard let bundledSurah = surahLookup[surah], !bundledSurah.ayahs.isEmpty else { return nil }
        return bundledSurah.ayahs.map { ayah in
            ayah.toQuranVerse(
                surahNumber: surah,
                includeEnglish: includeEnglish,
                audioURL: AudioURLBuilder.url(reciterID: reciterID, surah: surah, ayah: ayah.numberInSurah)
            )
        }
    }

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
