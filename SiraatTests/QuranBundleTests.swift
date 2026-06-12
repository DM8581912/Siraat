import XCTest
@testable import Siraat

final class QuranBundleTests: XCTestCase {
    private func loadBundle() throws -> QuranBundle {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "FullQuran", withExtension: "json"),
            "FullQuran.json must be bundled in the app target"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(QuranBundle.self, from: data)
    }

    func testBundleHasFullQuran() throws {
        let bundle = try loadBundle()
        XCTAssertEqual(bundle.surahs.count, 114)
        XCTAssertEqual(bundle.surahs.reduce(0) { $0 + $1.ayahs.count }, 6236)
    }

    func testSajdaCountIs15() throws {
        let bundle = try loadBundle()
        let sajdas = bundle.surahs.flatMap(\.ayahs).filter(\.sajda).count
        XCTAssertEqual(sajdas, 15)
    }

    func testFatihahMapsToQuranVerse() throws {
        let bundle = try loadBundle()
        let fatihah = try XCTUnwrap(bundle.surahs.first { $0.number == 1 })
        XCTAssertEqual(fatihah.ayahs.count, 7)
        XCTAssertTrue(fatihah.isMeccan)

        let verse = fatihah.ayahs[0].toQuranVerse(surahNumber: 1, includeEnglish: true, audioURL: nil)
        XCTAssertEqual(verse.verseKey, "1:1")
        XCTAssertEqual(verse.id, 1)
        XCTAssertFalse(verse.textUthmani.isEmpty)
        XCTAssertFalse(verse.translation.isEmpty)
    }
}
