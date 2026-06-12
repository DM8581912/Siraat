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
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var databaseManager: QuranDatabaseManaging?
    private var audioPlayer: QuranAudioPlayer?
    private var hasRestoredReadingPosition = false

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
        Task {
            guard let databaseManager else { return }
            isLoading = true
            defer { isLoading = false }

            do {
                settings = await databaseManager.readerSettings()
                bookmarks = await databaseManager.cachedBookmarks()
                readingPosition = await databaseManager.readingPosition()
                if let readingPosition, !hasRestoredReadingPosition {
                    selectedSurah = readingPosition.surahNumber
                    hasRestoredReadingPosition = true
                }
                verses = try await databaseManager.verses(
                    forSurah: selectedSurah,
                    language: settings.translationLanguage,
                    reciterID: settings.selectedReciterID
                )
                audioPlayer?.load(verses)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
        Task { await databaseManager?.saveReadingPosition(position) }
    }
}
