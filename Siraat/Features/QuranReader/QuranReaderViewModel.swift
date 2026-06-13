import Foundation

@MainActor
final class QuranReaderViewModel: ObservableObject {
    @Published var selectedSurah = 1
    @Published var searchText = ""
    @Published var showsBookmarksOnly = false
    @Published var settings: ReaderSettings = .default
    @Published private(set) var verses: [QuranVerse] = []
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var readingPosition: QuranReadingPosition?
    @Published private(set) var surahs: [BundledSurah] = []
    @Published private(set) var isLoading = false
    /// Credit for the translation actually displayed, and whether it is an offline English
    /// fallback. The reader shows these so text is never attributed to the wrong translator.
    @Published private(set) var translationCredit = TranslationLanguage.english.quranTranslationCredit
    @Published private(set) var isOfflineTranslationFallback = false
    @Published var errorMessage: String?
    /// Fatal load error that prevents the screen from rendering.
    @Published private(set) var loadError: String?
    /// verseKey the reader should scroll to (jump-to-ayah / start-of-juz).
    @Published var scrollTarget: String?

    private var databaseManager: QuranDatabaseManaging?
    private var audioPlayer: QuranAudioPlayer?
    private var hasRestoredReadingPosition = false
    private var persistPositionTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    var selectedChapter: QuranChapter {
        QuranChapter.chapter(number: selectedSurah)
    }

    var displayedVerses: [QuranVerse] {
        var result = verses

        if showsBookmarksOnly {
            let bookmarkedKeys = Set(bookmarks.map(\.verseKey))
            result = result.filter { bookmarkedKeys.contains($0.verseKey) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }

        let normalizedQuery = ArabicTextNormalizer.normalize(query).lowercased()
        return result.filter { verse in
            verse.verseKey.localizedCaseInsensitiveContains(query) ||
            verse.translation.localizedCaseInsensitiveContains(query) ||
            ArabicTextNormalizer.normalize(verse.textUthmani).lowercased().contains(normalizedQuery) ||
            ArabicTextNormalizer.normalize(verse.textIndopak).lowercased().contains(normalizedQuery)
        }
    }

    func configure(databaseManager: QuranDatabaseManaging, audioPlayer: QuranAudioPlayer) {
        guard self.databaseManager == nil else { return }
        self.databaseManager = databaseManager
        self.audioPlayer = audioPlayer
    }

    func load() {
        // Supersede any in-flight load: rapid surah/settings switches otherwise race, and
        // a slower earlier load could finish last and flash the wrong surah's verses.
        loadTask?.cancel()
        loadTask = Task {
            guard let databaseManager else { return }
            isLoading = true
            defer { isLoading = false }

            if surahs.isEmpty {
                surahs = await databaseManager.surahMetadata()
            }
            guard !Task.isCancelled else { return }

            do {
                settings = await databaseManager.readerSettings()
                bookmarks = await databaseManager.cachedBookmarks()
                readingPosition = await databaseManager.readingPosition()
                if let readingPosition, !hasRestoredReadingPosition {
                    selectedSurah = readingPosition.surahNumber
                    hasRestoredReadingPosition = true
                }
                let page = try await databaseManager.versePage(
                    forSurah: selectedSurah,
                    language: settings.translationLanguage,
                    reciterID: settings.selectedReciterID
                )
                guard !Task.isCancelled else { return }
                verses = page.verses
                translationCredit = page.translationCredit
                isOfflineTranslationFallback = page.isOfflineEnglishFallback
                loadError = nil
                audioPlayer?.load(verses)
            } catch {
                guard !Task.isCancelled else { return }
                loadError = error.localizedDescription
            }
        }
    }

    /// Jump to a surah (and optionally an ayah) — used by the Surah/Juz index.
    func jump(toSurah surah: Int, ayah: Int? = nil) {
        let target = ayah.map { "\(surah):\($0)" }
        if surah != selectedSurah {
            selectSurah(surah)
        }
        if let target { scrollTarget = target }
    }

    /// First verseKey of a juz, derived from the bundle's per-ayah juz metadata.
    func startOfJuz(_ juz: Int) -> (surah: Int, ayah: Int)? {
        for surah in surahs {
            if let ayah = surah.ayahs.first(where: { $0.juz == juz }) {
                return (surah.number, ayah.numberInSurah)
            }
        }
        return nil
    }

    func updateSettings(_ newSettings: ReaderSettings) {
        let shouldReloadContent = settings.translationLanguage != newSettings.translationLanguage ||
            settings.selectedReciterID != newSettings.selectedReciterID
        settings = newSettings
        Task {
            await databaseManager?.saveReaderSettings(newSettings)
            if shouldReloadContent {
                load()
            }
        }
    }

    func selectSurah(_ surah: Int) {
        selectedSurah = surah
        searchText = ""
        showsBookmarksOnly = false
        load()
    }

    func isBookmarked(_ verse: QuranVerse) -> Bool {
        bookmarks.contains { $0.verseKey == verse.verseKey }
    }

    func toggleBookmark(for verse: QuranVerse) {
        if let existing = bookmarks.firstIndex(where: { $0.verseKey == verse.verseKey }) {
            bookmarks.remove(at: existing)
        } else {
            bookmarks.append(Bookmark(verseKey: verse.verseKey))
        }

        Task { await databaseManager?.saveBookmarks(bookmarks) }
    }

    func markAsCurrent(_ verse: QuranVerse) {
        let position = QuranReadingPosition(
            surahNumber: verse.surahNumber,
            verseNumber: verse.verseNumber,
            verseKey: verse.verseKey
        )
        readingPosition = position

        // Debounce the persist: row appearance fires this rapidly during scroll, which
        // otherwise hammers storage and last-write-wins to the bottom-most visible row.
        persistPositionTask?.cancel()
        persistPositionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.databaseManager?.saveReadingPosition(position)
        }
    }
}
