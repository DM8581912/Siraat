import XCTest
@testable import Siraat

/// Counting mock — confined to the test target (first external conformer to the protocol).
private actor MockQuranDatabase: QuranDatabaseManaging {
    private(set) var saveReadingPositionCount = 0

    func verses(forSurah surah: Int, language: TranslationLanguage, reciterID: Int) throws -> [QuranVerse] { [] }
    func surahMetadata() -> [BundledSurah] { [] }
    func ayahs(inJuz juz: Int, language: TranslationLanguage, reciterID: Int) -> [QuranVerse] { [] }
    func cachedBookmarks() -> [Bookmark] { [] }
    func saveBookmarks(_ bookmarks: [Bookmark]) {}
    func readingPosition() -> QuranReadingPosition? { nil }
    func saveReadingPosition(_ position: QuranReadingPosition) { saveReadingPositionCount += 1 }
    func readerSettings() -> ReaderSettings { .default }
    func saveReaderSettings(_ settings: ReaderSettings) {}
}

@MainActor
final class QuranReaderViewModelTests: XCTestCase {
    func testReadingPositionPersistIsDebounced() async throws {
        let db = MockQuranDatabase()
        let viewModel = QuranReaderViewModel()
        viewModel.configure(databaseManager: db, audioPlayer: QuranAudioPlayer())

        let verse = QuranVerse(
            id: 1, surahNumber: 2, verseNumber: 1, verseKey: "2:1",
            textUthmani: "", textIndopak: "", translation: "", audioURL: nil
        )

        // Simulate rapid scroll firing markAsCurrent for many appearing rows.
        for _ in 0..<10 { viewModel.markAsCurrent(verse) }

        // Wait past the 400ms debounce window.
        try await Task.sleep(nanoseconds: 800_000_000)

        let count = await db.saveReadingPositionCount
        XCTAssertEqual(count, 1, "Rapid markAsCurrent calls should debounce to a single persist")
        XCTAssertEqual(viewModel.readingPosition?.verseKey, "2:1")
    }
}
