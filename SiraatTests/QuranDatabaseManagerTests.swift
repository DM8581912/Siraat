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
}
