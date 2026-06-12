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

    func testMissingNasalizationOnTanweenFiresGhunnahViolation() {
        let engine = TajweedRulesEngine()
        let observations = [
            TajweedPhonemeObservation(
                letter: "م",
                confidence: 0.72,
                duration: 0.18,
                hasNasalization: false,
                hasQalqalahBurst: false,
                articulationClass: "lips"
            )
        ]

        let violations = engine.violations(forWord: "عَلِيمٌ", wordIndex: 0, observations: observations)

        XCTAssertEqual(violations.first?.rule, .ghunnah)
        XCTAssertEqual(violations.first?.severity, .advisory)
    }

    func testMissingPlosiveBurstOnSukunDalFiresQalqalahViolation() {
        let engine = TajweedRulesEngine()
        let observations = [
            TajweedPhonemeObservation(
                letter: "د",
                confidence: 0.91,
                duration: 0.16,
                hasNasalization: false,
                hasQalqalahBurst: false,
                articulationClass: "tongue-front"
            )
        ]

        let violations = engine.violations(forWord: "أَحَدْ", wordIndex: 0, observations: observations)

        XCTAssertEqual(violations.first?.rule, .qalqalah)
        XCTAssertEqual(violations.first.map { String($0.affectedLetter) }, "د")
        XCTAssertEqual(violations.first?.severity, .critical)
    }

    func testShortDurationOnMaddLetterFiresMaddViolation() {
        let engine = TajweedRulesEngine()
        let observations = [
            TajweedPhonemeObservation(
                letter: "ا",
                confidence: 0.88,
                duration: 0.12,
                hasNasalization: false,
                hasQalqalahBurst: false,
                articulationClass: "throat"
            )
        ]

        let violations = engine.violations(forWord: "قَالَ", wordIndex: 0, observations: observations)

        XCTAssertEqual(violations.first?.rule, .madd)
        XCTAssertTrue(violations.first?.userFacingMessage.contains("too short") == true)
    }

    func testLowConfidenceViolationMapsToAdvisoryNeverCritical() {
        let engine = TajweedRulesEngine()
        let observations = [
            TajweedPhonemeObservation(
                letter: "د",
                confidence: 0.40,
                duration: 0.16,
                hasNasalization: false,
                hasQalqalahBurst: false,
                articulationClass: "tongue-front"
            )
        ]

        let violations = engine.violations(forWord: "أَحَدْ", wordIndex: 0, observations: observations)

        XCTAssertEqual(violations.first?.severity, .advisory)
        XCTAssertFalse(violations.contains { $0.severity == .critical })
    }

    func testHybridProviderFallsBackToTextTrackingWhenAnalyzerOutputsNothing() async {
        let provider = HybridRecitationAnalysisProvider(
            localMatcher: RecitationCorrectionService(),
            acousticAnalyzer: MockTajweedAcousticAnalyzer(observations: [:]),
            rulesEngine: TajweedRulesEngine()
        )
        let words = [
            RecitationWord(originalText: "ٱلْحَمْدُ"),
            RecitationWord(originalText: "لِلَّهِ")
        ]

        let result = await provider.analyze(transcript: "الحمد لله", expectedWords: words)

        XCTAssertEqual(result.engine, .localMatcher)
        XCTAssertEqual(result.words.map(\.status), [.correct, .correct])
        XCTAssertTrue(result.words.allSatisfy { $0.tajweedViolations.isEmpty })
    }

    func testHybridProviderAppendsMockedAcousticViolationsToWords() async {
        let provider = HybridRecitationAnalysisProvider(
            localMatcher: RecitationCorrectionService(),
            acousticAnalyzer: MockTajweedAcousticAnalyzer(
                observations: [
                    0: [
                        TajweedPhonemeObservation(
                            letter: "د",
                            confidence: 0.90,
                            duration: 0.16,
                            hasNasalization: false,
                            hasQalqalahBurst: false,
                            articulationClass: "tongue-front"
                        )
                    ]
                ]
            ),
            rulesEngine: TajweedRulesEngine()
        )
        let words = [RecitationWord(originalText: "أَحَدْ")]

        let result = await provider.analyze(transcript: "احد", expectedWords: words)

        XCTAssertEqual(result.engine, .coreML)
        XCTAssertEqual(result.words.first?.tajweedViolations.first?.rule, .qalqalah)
        XCTAssertEqual(result.words.first?.status, .missed)
    }
}
