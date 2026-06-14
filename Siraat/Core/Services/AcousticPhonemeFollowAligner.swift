import Foundation

/// A canonical phoneme of a verse, in reading order, tagged with the word it belongs to.
/// `token` is the acoustic model's vocabulary id for the expected phoneme.
///
/// NOTE: producing these token ids for a real verse — binding the verified phonetic blueprint
/// to the model's phoneme vocabulary — is part of the verified-corpus pipeline (and ideally the
/// model's own phonemizer), not something this engine guesses. This aligner operates on the
/// plan generically, so the algorithm is proven independently of that binding.
struct PlannedPhoneme: Equatable, Sendable {
    let token: Int
    let wordIndex: Int
}

/// Per-word acoustic follow result: the live state and an acoustic confidence (the fraction of
/// the word's canonical phonemes that were confidently heard in order).
struct AcousticWordFollow: Equatable, Sendable {
    let wordIndex: Int
    var state: FollowWordState
    var matchedFraction: Double
}

/// Phoneme-level acoustic follow-along.
///
/// This is the path that follows the *sound* of the recitation — the streaming frontend's heard
/// phoneme-token timeline aligned to a verse's canonical phoneme plan — rather than a general
/// recognizer's text. It is the accuracy ceiling above SFSpeech, because it never depends on a
/// model that was trained to hear Modern Standard Arabic words.
///
/// Honest by construction, like the word aligner: a word is only `correct` when enough of its
/// canonical phonemes align, in order, to heard phonemes of the same token; otherwise it stays
/// pending / uncertain. No hard "wrong" verdict is produced here — that remains the job of the
/// precision-first mistake detector. Pure Swift, deterministic, fully unit-tested.
struct AcousticPhonemeFollowAligner {
    /// Fraction of a word's canonical phonemes that must align for it to count as correct.
    var correctThreshold = 0.6

    private let exactCost = 0.0
    private let substituteCost = 1.8
    private let gapCost = 1.0

    func follow(plan: [PlannedPhoneme], heardTokens heard: [Int]) -> [AcousticWordFollow] {
        let wordCount = (plan.map(\.wordIndex).max() ?? -1) + 1
        guard wordCount > 0 else { return [] }

        var total = [Int](repeating: 0, count: wordCount)
        var matched = [Int](repeating: 0, count: wordCount)
        for phoneme in plan { total[phoneme.wordIndex] += 1 }

        let canonical = plan.map(\.token)
        let matchedFlags = alignMatched(canonical: canonical, heard: heard)
        for (index, isMatched) in matchedFlags.enumerated() where isMatched {
            matched[plan[index].wordIndex] += 1
        }

        var result: [AcousticWordFollow] = (0..<wordCount).map { word in
            let fraction = total[word] == 0 ? 0 : Double(matched[word]) / Double(total[word])
            let state: FollowWordState = fraction >= correctThreshold
                ? .correct
                : (fraction > 0 ? .uncertain : .pending)
            return AcousticWordFollow(wordIndex: word, state: state, matchedFraction: fraction)
        }
        // The head: the first word not yet confirmed is where the reciter is.
        if let head = result.firstIndex(where: { $0.state != .correct }) {
            result[head].state = .active
        }
        return result
    }

    /// Monotonic Needleman–Wunsch alignment of the heard token sequence to the canonical token
    /// sequence; returns, for each canonical phoneme, whether it aligned to a heard phoneme of
    /// the same token. Insertions (extra heard phonemes), deletions (canonical not heard), and
    /// substitutions (heard a different phoneme) are all allowed.
    private func alignMatched(canonical: [Int], heard: [Int]) -> [Bool] {
        let n = canonical.count, m = heard.count
        guard n > 0 else { return [] }
        guard m > 0 else { return [Bool](repeating: false, count: n) }

        var cost = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        var op = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1) // 0 diag, 1 up (delete canonical), 2 left (insert heard)
        for i in 1...n { cost[i][0] = Double(i) * gapCost; op[i][0] = 1 }
        for j in 1...m { cost[0][j] = Double(j) * gapCost; op[0][j] = 2 }

        for i in 1...n {
            for j in 1...m {
                let same = canonical[i - 1] == heard[j - 1]
                let diag = cost[i - 1][j - 1] + (same ? exactCost : substituteCost)
                let up = cost[i - 1][j] + gapCost
                let left = cost[i][j - 1] + gapCost
                if diag <= up && diag <= left { cost[i][j] = diag; op[i][j] = 0 }
                else if up <= left { cost[i][j] = up; op[i][j] = 1 }
                else { cost[i][j] = left; op[i][j] = 2 }
            }
        }

        var flags = [Bool](repeating: false, count: n)
        var i = n, j = m
        while i > 0 || j > 0 {
            switch op[i][j] {
            case 0:
                flags[i - 1] = canonical[i - 1] == heard[j - 1]
                i -= 1; j -= 1
            case 1:
                i -= 1
            default:
                j -= 1
            }
        }
        return flags
    }
}

/// Maps each base-letter cluster of an Uthmani ayah (in reading order) to the index of the word
/// it belongs to. Safe and content-free: it only counts base-letter clusters per space-separated
/// word — no phonetic interpretation. Combined with a verified blueprint→token binding (corpus
/// work), this yields the per-word `PlannedPhoneme`s the acoustic aligner consumes.
enum PhonemeWordMap {
    static func wordIndices(forUthmani uthmani: String) -> [Int] {
        var indices: [Int] = []
        for (wordIndex, word) in uthmani.split(separator: " ").enumerated() {
            let clusterCount = UthmaniCharacterMapper.clusters(in: String(word)).count
            indices.append(contentsOf: Array(repeating: wordIndex, count: clusterCount))
        }
        return indices
    }
}
