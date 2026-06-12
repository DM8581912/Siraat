import XCTest
@testable import Siraat

final class QuranDatabaseManagerTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SiraatTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPersistsReadingPosition() async {
        let manager = QuranDatabaseManager(userDefaults: userDefaults)
        let position = QuranReadingPosition(surahNumber: 2, verseNumber: 255, verseKey: "2:255")

        await manager.saveReadingPosition(position)
        let restored = await manager.readingPosition()

        XCTAssertEqual(restored?.surahNumber, 2)
        XCTAssertEqual(restored?.verseNumber, 255)
        XCTAssertEqual(restored?.verseKey, "2:255")
    }

    func testPersistsReaderSettings() async {
        let manager = QuranDatabaseManager(userDefaults: userDefaults)
        let settings = ReaderSettings(
            script: .indopak,
            readingMode: .page,
            fontSize: 34,
            translationLanguage: .urdu,
            selectedReciterID: QuranReciter.sudais.rawValue,
            appearanceMode: .dark
        )

        await manager.saveReaderSettings(settings)
        let restored = await manager.readerSettings()

        XCTAssertEqual(restored, settings)
    }

    func testBundleLoadsFatihahOffline() async throws {
        let manager = QuranDatabaseManager(userDefaults: userDefaults)
        let verses = try await manager.verses(forSurah: 1, language: .english, reciterID: QuranReciter.misharyAlafasy.rawValue)

        XCTAssertEqual(verses.count, 7)
        XCTAssertEqual(verses.first?.verseKey, "1:1")
        XCTAssertFalse(verses.first?.textUthmani.isEmpty ?? true)
        XCTAssertFalse(verses.first?.translation.isEmpty ?? true)
        XCTAssertEqual(verses.first?.audioURL?.absoluteString, "https://everyayah.com/data/Alafasy_128kbps/001001.mp3")
    }

    func testSurahMetadataHas114Surahs() async {
        let manager = QuranDatabaseManager(userDefaults: userDefaults)
        let meta = await manager.surahMetadata()
        XCTAssertEqual(meta.count, 114)
    }

    func testJuz30StartsAtAnNaba() async {
        let manager = QuranDatabaseManager(userDefaults: userDefaults)
        let ayahs = await manager.ayahs(inJuz: 30, language: .english, reciterID: QuranReciter.misharyAlafasy.rawValue)
        XCTAssertEqual(ayahs.first?.verseKey, "78:1")
    }

    func testVerseByGlobalNumber() async {
        let manager = QuranDatabaseManager(userDefaults: userDefaults)
        let first = await manager.verse(globalNumber: 1)
        XCTAssertEqual(first?.verseKey, "1:1")
        let last = await manager.verse(globalNumber: 6236)
        XCTAssertEqual(last?.verseKey, "114:6")
    }
}
