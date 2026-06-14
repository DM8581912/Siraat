import XCTest
@testable import Siraat

/// The acoustic follow aligner is the path that follows the *sound* of the recitation. These
/// tests pin its phoneme-to-word logic deterministically with synthetic token sequences (no
/// model, no audio), so the algorithm is proven in CI independently of the corpus binding.
final class AcousticPhonemeFollowAlignerTests: XCTestCase {
    private let aligner = AcousticPhonemeFollowAligner()

    // word 0 = phonemes [1,2], word 1 = [3,4], word 2 = [5,6]
    private func plan() -> [PlannedPhoneme] {
        [
            PlannedPhoneme(token: 1, wordIndex: 0), PlannedPhoneme(token: 2, wordIndex: 0),
            PlannedPhoneme(token: 3, wordIndex: 1), PlannedPhoneme(token: 4, wordIndex: 1),
            PlannedPhoneme(token: 5, wordIndex: 2), PlannedPhoneme(token: 6, wordIndex: 2)
        ]
    }

    func testAllPhonemesHeardAllWordsCorrect() {
        let result = aligner.follow(plan: plan(), heardTokens: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(result.map(\.state), [.correct, .correct, .correct])
        XCTAssertTrue(result.allSatisfy { $0.matchedFraction == 1.0 })
    }

    func testPartialRecitationMarksHeadActiveAndRestPending() {
        // Only the first word was heard.
        let result = aligner.follow(plan: plan(), heardTokens: [1, 2])
        XCTAssertEqual(result[0].state, .correct)
        XCTAssertEqual(result[1].state, .active)   // the head — where the reciter is
        XCTAssertEqual(result[2].state, .pending)
        XCTAssertEqual(result[0].matchedFraction, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result[1].matchedFraction, 0.0, accuracy: 1e-9)
    }

    func testWordWhosePhonemesWereNotHeardIsNotConfirmed() {
        // Word 0 heard; word 1 mispronounced (wrong phonemes); word 2 not yet reached.
        let result = aligner.follow(plan: plan(), heardTokens: [1, 2, 9, 9])
        XCTAssertEqual(result[0].state, .correct)
        XCTAssertNotEqual(result[1].state, .correct) // never falsely confirmed
        XCTAssertEqual(result[1].matchedFraction, 0.0, accuracy: 1e-9)
    }

    func testInsertedNoisePhonemesDoNotBreakConfirmation() {
        // Extra heard phonemes between words (coarticulation / noise) must not stop the words
        // from being confirmed.
        let result = aligner.follow(plan: plan(), heardTokens: [1, 2, 0, 0, 3, 4, 0, 5, 6])
        XCTAssertEqual(result.map(\.state), [.correct, .correct, .correct])
    }

    func testEmptyHeardIsAllPendingWithActiveHead() {
        let result = aligner.follow(plan: plan(), heardTokens: [])
        XCTAssertEqual(result[0].state, .active)
        XCTAssertEqual(result.dropFirst().map(\.state), [.pending, .pending])
    }

    func testConfidenceFractionReflectsPartialMatch() {
        // word 0 has three phonemes; only one is heard -> fraction 1/3, below the 0.6 threshold.
        let p = [
            PlannedPhoneme(token: 1, wordIndex: 0), PlannedPhoneme(token: 2, wordIndex: 0), PlannedPhoneme(token: 3, wordIndex: 0),
            PlannedPhoneme(token: 4, wordIndex: 1), PlannedPhoneme(token: 5, wordIndex: 1)
        ]
        let result = aligner.follow(plan: p, heardTokens: [1, 7, 7, 4, 5])
        XCTAssertEqual(result[0].matchedFraction, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertNotEqual(result[0].state, .correct)
        XCTAssertEqual(result[1].state, .correct)
    }

    // MARK: word-index mapping (safe, content-free)

    func testWordIndicesMapClustersToWordsInReadingOrder() {
        // Al-Fatiha 1:1 — four words. We assert structure, not hand-counted cluster totals.
        let indices = PhonemeWordMap.wordIndices(forUthmani: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
        XCTAssertFalse(indices.isEmpty)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.max(), 3) // four words, indices 0...3
        // Monotonic non-decreasing: phonemes are tagged in reading order.
        XCTAssertEqual(indices, indices.sorted())
        // Every word contributes at least one cluster.
        XCTAssertEqual(Set(indices), Set(0...3))
    }
}
