import Foundation

/// Live follow-along state for one expected word.
enum FollowWordState: String, Equatable, Sendable {
    case pending      // not yet reached by the reciter
    case active       // the alignment head — currently being recited (drives the karaoke highlight)
    case correct      // confidently matched, in order
    case uncertain    // reached but not confidently matched (skipped / substituted / unclear)
}

/// One expected word's follow-along result: its live state, which spoken token it matched
/// (for the highlight), and how confident that match is.
struct FollowWord: Equatable, Sendable {
    let index: Int
    var state: FollowWordState
    var matchedTokenIndex: Int?
    var confidence: Double
}

/// Robust word-level forced alignment of a reciter's running transcript against the expected
/// word sequence of the selected passage.
///
/// This replaces position-based index matching, which collapses the moment the token stream
/// shifts: a leading isti'adha or basmala, a repeated word, or a skipped word throws every
/// later `spoken[i] == expected[i]` comparison off by one. Instead we compute a monotonic
/// global alignment (Needleman–Wunsch) that allows:
///   - insertions: extra tokens the reciter said (a'udhu billah, a repeat) — consumed, not penalized into the verse,
///   - deletions: words the reciter skipped,
///   - fuzzy matches: recognizer slips on classical Arabic (within `fuzzyDistance` edits).
///
/// It is honest by construction: an unmatched expected word is left `uncertain`, never accused.
/// Hard "you said this wrong" verdicts are a separate, higher-precision stage (mistake
/// detection) — this engine's job is to *follow*, robustly, and to never tell a correct
/// reciter they erred. Pure Swift and deterministic: no acoustic model, no audio, fully
/// testable. The same alignment drives the live mushaf highlight via `matchedTokenIndex`.
struct StreamingRecitationAligner {
    /// Normalized tokens within this edit distance count as the same word (recognizer slips).
    var fuzzyDistance = 1

    // Alignment costs. A real substitution (different word in place) is cheaper than a
    // delete+insert pair, so a substituted word stays in its slot (flagged uncertain) rather
    // than shifting the whole tail.
    private let exactCost = 0.0
    private let fuzzyCost = 0.4
    private let substituteCost = 1.8
    private let gapCost = 1.0

    /// Align the reciter's transcript to the expected words. Both sides are normalized
    /// (diacritics stripped, letter forms unified) before alignment.
    func align(expected: [String], transcript: String) -> [FollowWord] {
        let spoken = ArabicTextNormalizer.tokens(from: transcript)
        let target = expected.map { ArabicTextNormalizer.tokens(from: $0).first ?? "" }
        return align(targetTokens: target, spokenTokens: spoken)
    }

    /// Core alignment over already-normalized token sequences.
    func align(targetTokens target: [String], spokenTokens spoken: [String]) -> [FollowWord] {
        let n = target.count
        let m = spoken.count
        guard n > 0 else { return [] }

        // Nothing heard yet: everything pending, the first word is active.
        guard m > 0 else {
            return (0..<n).map { FollowWord(index: $0, state: $0 == 0 ? .active : .pending, matchedTokenIndex: nil, confidence: 0) }
        }

        // op[i][j]: how cell (i,j) was reached. 0 = diagonal (match/sub), 1 = up (delete
        // expected i), 2 = left (insert spoken j).
        var cost = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        var op = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { cost[i][0] = Double(i) * gapCost; op[i][0] = 1 }
        for j in 1...m { cost[0][j] = Double(j) * gapCost; op[0][j] = 2 }

        for i in 1...n {
            for j in 1...m {
                let diag = cost[i - 1][j - 1] + matchCost(target[i - 1], spoken[j - 1])
                let up = cost[i - 1][j] + gapCost      // expected word i skipped
                let left = cost[i][j - 1] + gapCost    // spoken token j inserted
                if diag <= up && diag <= left {
                    cost[i][j] = diag; op[i][j] = 0
                } else if up <= left {
                    cost[i][j] = up; op[i][j] = 1
                } else {
                    cost[i][j] = left; op[i][j] = 2
                }
            }
        }

        // Backtrack, assigning each expected word its match (or marking it skipped).
        var words = (0..<n).map { FollowWord(index: $0, state: .uncertain, matchedTokenIndex: nil, confidence: 0) }
        var i = n, j = m
        while i > 0 || j > 0 {
            switch op[i][j] {
            case 0:
                let kind = pairKind(target[i - 1], spoken[j - 1])
                words[i - 1] = resolve(index: i - 1, spokenIndex: j - 1, kind: kind)
                i -= 1; j -= 1
            case 1:
                // Expected word i-1 was skipped: reached but unmatched -> uncertain (never a
                // hard verdict here).
                words[i - 1] = FollowWord(index: i - 1, state: .uncertain, matchedTokenIndex: nil, confidence: 0)
                i -= 1
            default:
                j -= 1   // an inserted spoken token (isti'adha / basmala / repeat): consumed
            }
        }

        annotateActive(&words)
        return words
    }

    // MARK: - Alignment-head highlight

    /// Marks the live highlight: the word after the last confidently matched one becomes
    /// `active`; words past the head that were never matched stay `pending` rather than
    /// `uncertain` (the reciter simply has not reached them yet).
    private func annotateActive(_ words: inout [FollowWord]) {
        let lastMatched = words.lastIndex { $0.state == .correct || $0.matchedTokenIndex != nil }
        guard let lastMatched else {
            if !words.isEmpty { words[0].state = .active }
            return
        }
        for index in (lastMatched + 1)..<words.count where words[index].matchedTokenIndex == nil {
            words[index].state = .pending
        }
        let head = lastMatched + 1
        if head < words.count { words[head].state = .active }
    }

    // MARK: - Match classification

    private enum PairKind { case exact, fuzzy, substitution }

    private func pairKind(_ target: String, _ spoken: String) -> PairKind {
        if target == spoken { return .exact }
        if isFuzzy(target, spoken) { return .fuzzy }
        return .substitution
    }

    private func matchCost(_ target: String, _ spoken: String) -> Double {
        switch pairKind(target, spoken) {
        case .exact: return exactCost
        case .fuzzy: return fuzzyCost
        case .substitution: return substituteCost
        }
    }

    private func resolve(index: Int, spokenIndex: Int, kind: PairKind) -> FollowWord {
        switch kind {
        case .exact:
            return FollowWord(index: index, state: .correct, matchedTokenIndex: spokenIndex, confidence: 1.0)
        case .fuzzy:
            // Heard within one edit of the expected word: a follow match (likely a recognizer
            // slip), confirmed for follow purposes but not asserted as flawless.
            return FollowWord(index: index, state: .correct, matchedTokenIndex: spokenIndex, confidence: 0.75)
        case .substitution:
            // A different word sits in this slot. Reached but not confirmed — uncertain, never
            // a hard verdict. Mistake detection is a separate, higher-precision stage.
            return FollowWord(index: index, state: .uncertain, matchedTokenIndex: spokenIndex, confidence: 0.2)
        }
    }

    private func isFuzzy(_ lhs: String, _ rhs: String) -> Bool {
        // Cheap length-difference reject before the full edit distance.
        if abs(lhs.count - rhs.count) > fuzzyDistance { return false }
        return Self.levenshtein(Array(lhs), Array(rhs)) <= fuzzyDistance
    }

    static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
