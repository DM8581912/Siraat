import XCTest
@testable import Siraat

final class RecitationCorrectionServiceTests: XCTestCase {
    func testEvaluateMarksMatchingWordsCorrect() {
        let service = RecitationCorrectionService()
        let words = [
            RecitationWord(originalText: "ٱلْحَمْدُ"),
            RecitationWord(originalText: "لِلَّهِ")
        ]

        let result = service.evaluate(transcript: "الحمد لله", expectedWords: words)

        XCTAssertEqual(result.map(\.status), [.correct, .correct])
    }

    func testEvaluateMarksCloseWordsUncertain() {
        let service = RecitationCorrectionService()
        let words = [RecitationWord(originalText: "ٱلرَّحْمَـٰنِ")]

        let result = service.evaluate(transcript: "الرحمنن", expectedWords: words)

        XCTAssertEqual(result.first?.status, .uncertain)
        XCTAssertNotNil(result.first?.tip)
    }

    func testPrepareWordsUsesSelectedScript() {
        let service = RecitationCorrectionService()
        let verse = QuranVerse(
            id: 1,
            surahNumber: 1,
            verseNumber: 1,
            verseKey: "1:1",
            textUthmani: "بِسْمِ ٱللَّهِ",
            textIndopak: "بِسْمِ اللّٰهِ",
            translation: "",
            audioURL: nil
        )

        let words = service.prepareWords(for: verse, script: .uthmani)

        XCTAssertEqual(words.map(\.originalText), ["بِسْمِ", "ٱللَّهِ"])
    }
}
