import XCTest
@testable import Siraat

final class ForcedAlignerTests: XCTestCase {
    private func blueprint() -> AyahPhonemeMap {
        AyahPhonemeMap(
            verseKey: "test:1",
            scriptUthmani: "بَا",
            source: BlueprintProvenance(corpus: "test", attribution: "test", verified: true),
            phonemes: [
                CanonicalPhoneme(symbol: "b", baseLetter: "ب", isMaddVowel: false, expectedMaddCount: 0, expectedDurationSeconds: 0.18),
                CanonicalPhoneme(symbol: "A", baseLetter: "ا", isMaddVowel: true, expectedMaddCount: 2, expectedDurationSeconds: 0.9)
            ]
        )
    }

    func testPlaceholderAlignmentMatchesBlueprintAndReadsGreen() async throws {
        let aligner = CoreMLForcedAligner()
        let aligned = try await aligner.align(samples: [], sampleRate: 16_000, against: blueprint())
        XCTAssertEqual(aligned.count, 2)
        XCTAssertEqual(aligned[0].baseLetter, "ب")
        XCTAssertEqual(aligned[1].duration, 0.9, accuracy: 0.0001)

        // The placeholder must never invent an error.
        let results = CharacterTajweedEvaluator().evaluate(uthmani: "بَا", blueprint: blueprint(), aligned: aligned)
        XCTAssertEqual(results.map(\.color), [.green, .green])
    }

    func testCTCAlignmentProducesMonotonicSpansForEachToken() {
        // 4 frames, 3 vocab tokens. Token 1 peaks early, token 2 peaks late.
        let emissions: [[Float]] = [
            [0.1, 0.8, 0.1],
            [0.1, 0.7, 0.2],
            [0.1, 0.2, 0.7],
            [0.1, 0.1, 0.8]
        ]
        let spans = CTCForcedAligner().align(emissions: emissions, targetTokens: [1, 2])
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].startFrame, 0)
        XCTAssertEqual(spans[1].endFrame, emissions.count)
        XCTAssertLessThanOrEqual(spans[0].endFrame, spans[1].startFrame)
    }

    func testCTCAlignmentEmptyInputsReturnEmpty() {
        XCTAssertTrue(CTCForcedAligner().align(emissions: [], targetTokens: [1]).isEmpty)
        XCTAssertTrue(CTCForcedAligner().align(emissions: [[0.1]], targetTokens: []).isEmpty)
    }

    func testHybridProviderProducesCharacterResultsFromBlueprint() async {
        let provider = HybridRecitationAnalysisProvider()
        let results = await provider.analyzeCharacters(
            uthmani: "بَا",
            blueprint: blueprint(),
            samples: [],
            sampleRate: 16_000
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.color), [.green, .green])
    }

    func testDefaultProviderReturnsNoCharacterResults() async {
        // A provider that only implements word analysis inherits the empty default.
        struct WordsOnlyProvider: RecitationAnalysisProviding {
            func analyze(transcript: String, expectedWords: [RecitationWord]) async -> RecitationAnalysisResult {
                RecitationAnalysisResult(words: expectedWords, engine: .localMatcher)
            }
        }
        let results = await WordsOnlyProvider().analyzeCharacters(
            uthmani: "بَا",
            blueprint: blueprint(),
            samples: [],
            sampleRate: 16_000
        )
        XCTAssertTrue(results.isEmpty)
    }
}
