import Foundation

/// What kind of mistake was detected.
enum MistakeKind: String, Codable, Equatable, Sendable {
    case skipped         // an expected word was not recited
    case substituted     // a different word was recited in this slot
    case added           // an extra word was recited that is not in the expected verse
                         // (and not a known optional like istiʿādha / basmala fragments)
}

/// One precision-first mistake verdict. The reciter is never told they erred unless we are
/// sure — only verdicts at or above the detector's precision floor are emitted.
struct MistakeFinding: Equatable, Sendable {
    let kind: MistakeKind
    /// Which expected word index this concerns. `nil` for `.added` (no expected slot).
    let expectedWordIndex: Int?
    /// Index into the transcript's spoken tokens. `nil` for `.skipped` (nothing was said).
    let spokenTokenIndex: Int?
    /// What the reciter said (for `.substituted` / `.added`) — diacritics-free.
    let spokenToken: String?
    /// Confidence in this verdict. The default critical floor is 0.85; anything below is dropped.
    let confidence: Double
}

/// Honest, precision-first mistake detection over the streaming forced-alignment trace.
///
/// Tarteel's flagship feature is word-level skip / wrong / added detection. This detector
/// matches that taxonomy, but is precision-first by construction: a hard verdict is only
/// emitted when several independent evidence checks line up — the reciter has demonstrably
/// moved past the word in question, the heard token is not a fuzzy match of any nearby
/// expected word (so a recognizer slip cannot become a false accusation), it is not a
/// recognized recitation optional (isti'ādha, basmala fragments before a non-Fatiha verse),
/// and it is not a stutter-repeat of a word the reciter already correctly said. Anything
/// short of that stays `uncertain` — never `.missed`.
///
/// Pure Swift, deterministic, no audio, no model. The detector is the math; live use adds a
/// stateful confirmation buffer (`StreamingMistakeConfirmer`) on top so a verdict only fires
/// after the alignment has reported the same finding for two consecutive transcript ticks.
struct RecitationMistakeDetector {
    var precisionFloor: Double = 0.85
    var aligner = StreamingRecitationAligner()
    /// Stutter window: an unused spoken token within `repeatWindow` positions of a token that
    /// did match an expected word is treated as a stutter-repeat, never an "added" mistake.
    var repeatWindow: Int = 2

    /// Tokens we will never flag as "added" — recitation optionals a Muslim may legitimately
    /// say before an ayah (the isti'ādha is recommended before any recitation; the basmala is
    /// recited before every surah but the ninth). Normalized: diacritics stripped, letter
    /// forms unified (ٱ/أ/إ/آ → ا, etc.). Kept small and explicit; expansion belongs in the
    /// verified corpus, not here.
    static let knownOptionals: Set<String> = [
        // istiʿādha (a'ūdhu billāhi min ash-shayṭān ar-rajīm)
        "اعوذ", "بالله", "من", "الشيطان", "الرجيم",
        // basmala (bismi-llāhi r-raḥmān ar-raḥīm)
        "بسم", "الله", "الرحمن", "الرحيم"
    ]

    func detect(expected: [String], transcript: String) -> [MistakeFinding] {
        let spoken = ArabicTextNormalizer.tokens(from: transcript)
        let follow = aligner.align(expected: expected, transcript: transcript)
        return detect(expected: expected, spokenTokens: spoken, follow: follow)
    }

    func detect(
        expected: [String],
        spokenTokens spoken: [String],
        follow: [FollowWord]
    ) -> [MistakeFinding] {
        guard !follow.isEmpty else { return [] }
        var findings: [MistakeFinding] = []

        // The alignment head: the furthest expected index we have confidently confirmed. Skips
        // and substitutions are only "confirmed past" up to here — beyond, the reciter may
        // still be on their way and we stay silent.
        let lastConfirmed = follow.lastIndex { $0.state == .correct } ?? -1
        let expectedNormalized = expected.map { ArabicTextNormalizer.tokens(from: $0).first ?? "" }
        let usedIndices = Set(follow.compactMap(\.matchedTokenIndex))

        // 1) Skips — expected words with no match, lying before the alignment head.
        //    Evidence: the reciter has gone past this word (a later word is confirmed) and
        //    nothing in the transcript bound to this slot. High confidence by construction.
        for word in follow
        where word.index < lastConfirmed
            && word.matchedTokenIndex == nil
            && word.state == .uncertain {
            findings.append(
                MistakeFinding(
                    kind: .skipped,
                    expectedWordIndex: word.index,
                    spokenTokenIndex: nil,
                    spokenToken: nil,
                    confidence: 0.95
                )
            )
        }

        // 2) Substitutions — matched slot, but the heard token clearly isn't this word and
        //    isn't a fuzzy match of any expected word in the verse. The second check is the
        //    honesty gate: if what was heard could plausibly belong to a nearby slot, we
        //    suspect mis-attribution and stay silent rather than risk a false accusation.
        for word in follow
        where word.state == .uncertain
            && word.matchedTokenIndex != nil
            && word.index <= lastConfirmed + 1 {
            guard let tokenIdx = word.matchedTokenIndex, tokenIdx < spoken.count else { continue }
            let heard = spoken[tokenIdx]
            if expectedNormalized.contains(where: { fuzzyEqual($0, heard) }) { continue }
            findings.append(
                MistakeFinding(
                    kind: .substituted,
                    expectedWordIndex: word.index,
                    spokenTokenIndex: tokenIdx,
                    spokenToken: heard,
                    confidence: 0.9
                )
            )
        }

        // 3) Added — spoken tokens not bound to any expected word that are also not (a) a
        //    recognition optional, (b) a fuzzy match of any expected word (the aligner may
        //    have placed it elsewhere), or (c) a stutter-repeat of a nearby word the reciter
        //    did say correctly. All three escape hatches exist because telling a Muslim they
        //    "added a word" when they were reciting a sunnah opening or stuttering would be
        //    the exact failure CLAUDE.md forbids.
        for (idx, token) in spoken.enumerated() where !usedIndices.contains(idx) {
            if Self.knownOptionals.contains(token) { continue }
            if expectedNormalized.contains(where: { fuzzyEqual($0, token) }) { continue }
            if isStutterRepeat(idx: idx, token: token, spoken: spoken, used: usedIndices) { continue }
            findings.append(
                MistakeFinding(
                    kind: .added,
                    expectedWordIndex: nil,
                    spokenTokenIndex: idx,
                    spokenToken: token,
                    confidence: 0.85
                )
            )
        }

        return findings.filter { $0.confidence >= precisionFloor }
    }

    /// True if this unused token is the same (within one edit) as a nearby matched token —
    /// the reciter repeated a word they already correctly recited. Never a mistake.
    private func isStutterRepeat(
        idx: Int,
        token: String,
        spoken: [String],
        used: Set<Int>
    ) -> Bool {
        let lower = max(0, idx - repeatWindow)
        let upper = min(spoken.count - 1, idx + repeatWindow)
        guard lower <= upper else { return false }
        for other in lower...upper where other != idx && used.contains(other) {
            if fuzzyEqual(spoken[other], token) { return true }
        }
        return false
    }

    private func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if abs(a.count - b.count) > 1 { return false }
        return StreamingRecitationAligner.levenshtein(Array(a), Array(b)) <= 1
    }
}

/// Stateful streaming layer over `RecitationMistakeDetector` for live use.
///
/// In a live session the transcript grows tick by tick. A finding present at tick N may
/// vanish at tick N+1 once the next word arrives and the alignment refines. The confirmer
/// only releases a finding to the UI after it has appeared in `confirmationsRequired`
/// consecutive analyses — anti-flicker, honesty under jitter. Once confirmed a finding stays
/// stuck (we don't unsay a hard verdict mid-session); call `reset()` between sessions.
final class StreamingMistakeConfirmer {
    var confirmationsRequired: Int = 2

    private var pendingHits: [String: Int] = [:]
    private var confirmed: Set<String> = []

    /// Feed the per-tick findings; receive the subset that has cleared the confirmation
    /// threshold (newly or previously). The returned array is the live set.
    func ingest(_ findings: [MistakeFinding]) -> [MistakeFinding] {
        let keysThisTick = Set(findings.map(Self.key))
        // A finding that disappeared this tick loses its pending count — the evidence is gone.
        pendingHits = pendingHits.filter { keysThisTick.contains($0.key) }

        var out: [MistakeFinding] = []
        for finding in findings {
            let key = Self.key(finding)
            if confirmed.contains(key) {
                out.append(finding)
                continue
            }
            let count = (pendingHits[key] ?? 0) + 1
            pendingHits[key] = count
            if count >= confirmationsRequired {
                confirmed.insert(key)
                pendingHits.removeValue(forKey: key)
                out.append(finding)
            }
        }
        return out
    }

    func reset() {
        pendingHits.removeAll()
        confirmed.removeAll()
    }

    private static func key(_ f: MistakeFinding) -> String {
        switch f.kind {
        case .skipped:
            return "skip:\(f.expectedWordIndex ?? -1)"
        case .substituted:
            return "sub:\(f.expectedWordIndex ?? -1):\(f.spokenToken ?? "")"
        case .added:
            return "add:\(f.spokenTokenIndex ?? -1):\(f.spokenToken ?? "")"
        }
    }
}
