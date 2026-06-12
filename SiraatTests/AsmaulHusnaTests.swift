import XCTest
@testable import Siraat

final class AsmaulHusnaTests: XCTestCase {
    func testHas99Names() {
        XCTAssertEqual(AsmaulHusna.all.count, 99)
    }

    func testNamesAreSequentialAndComplete() {
        for (index, name) in AsmaulHusna.all.enumerated() {
            XCTAssertEqual(name.id, index + 1)
            XCTAssertFalse(name.arabic.isEmpty)
            XCTAssertFalse(name.transliteration.isEmpty)
            XCTAssertFalse(name.meaning.isEmpty)
        }
    }
}
