import XCTest
@testable import Siraat

final class UthmaniCharacterMapperTests: XCTestCase {
    func testGroupsBaseLetterWithCombiningMarks() {
        // meem + shaddah + fatha + dagger alef → one cluster, flagged as a Madd.
        let text = "مَّٰ"
        let clusters = UthmaniCharacterMapper.clusters(in: text)
        XCTAssertEqual(clusters.count, 1)
        let cluster = clusters[0]
        XCTAssertEqual(cluster.baseLetter, "م")
        XCTAssertTrue(cluster.isMaddCluster)
        XCTAssertEqual(cluster.text, text)
        XCTAssertEqual(cluster.utf16Range, 0..<(text as NSString).length)
    }

    func testSkipsSpacesButKeepsUTF16OffsetsAligned() {
        let text = "ا ب"
        let clusters = UthmaniCharacterMapper.clusters(in: text)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].baseLetter, "ا")
        XCTAssertEqual(clusters[0].utf16Range, 0..<1)
        XCTAssertEqual(clusters[1].baseLetter, "ب")
        // The space at offset 1 is skipped; ب sits at UTF-16 offset 2.
        XCTAssertEqual(clusters[1].utf16Range, 2..<3)
    }

    func testNormalizesAlefWaslaBaseLetter() {
        let clusters = UthmaniCharacterMapper.clusters(in: "ٱ")
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].baseLetter, "ا")
    }

    func testLeadingBOMDoesNotCreateCluster() {
        let text = "\u{FEFF}بِ"
        let clusters = UthmaniCharacterMapper.clusters(in: text)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].baseLetter, "ب")
    }
}
