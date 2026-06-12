import XCTest
@testable import Siraat

final class QuranChapterTests: XCTestCase {
    func testContainsAllChapters() {
        XCTAssertEqual(QuranChapter.all.count, 114)
        XCTAssertEqual(QuranChapter.chapter(number: 1).transliteratedName, "Al-Fatihah")
        XCTAssertEqual(QuranChapter.chapter(number: 2).verseCount, 286)
        XCTAssertEqual(QuranChapter.chapter(number: 114).englishName, "Mankind")
    }
}
