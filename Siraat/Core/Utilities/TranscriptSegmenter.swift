import Foundation

/// Splits a live, continuously-rewritten speech transcript into completed sentences.
///
/// SFSpeechRecognizer doesn't only append — it can rewrite earlier words as it gains
/// confidence. Tracking progress by character *count* breaks when the transcript is
/// replaced by different text of similar length (the old offset then points into the
/// middle of unrelated text). Instead we remember the actual emitted text prefix and, if
/// a new transcript no longer begins with it, treat it as a fresh transcript and restart.
struct TranscriptSegmenter {
    /// The portion of the transcript already emitted, up to and including the last
    /// sentence delimiter (or the whole transcript after a final flush).
    private var emittedText = ""
    private let delimiters = CharacterSet(charactersIn: ".!?؟۔\n")

    mutating func reset() {
        emittedText = ""
    }

    mutating func consume(_ text: String, isFinal: Bool) -> [String] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        // If the recognizer rewrote/shrank the transcript so it no longer starts with
        // what we've already emitted, start over from the beginning of the new text.
        if !normalized.hasPrefix(emittedText) {
            emittedText = ""
        }

        // Only scan the not-yet-emitted remainder.
        let remainderStart = normalized.index(normalized.startIndex, offsetBy: emittedText.count)
        var segments: [String] = []
        var segmentStart = remainderStart
        var cursor = remainderStart

        while cursor < normalized.endIndex {
            let scalar = normalized[cursor].unicodeScalars.first
            if let scalar, delimiters.contains(scalar) {
                let end = normalized.index(after: cursor)
                appendSegment(String(normalized[segmentStart..<end]), to: &segments)
                segmentStart = end
                emittedText = String(normalized[normalized.startIndex..<end])
            }
            cursor = normalized.index(after: cursor)
        }

        if isFinal, segmentStart < normalized.endIndex {
            appendSegment(String(normalized[segmentStart..<normalized.endIndex]), to: &segments)
            emittedText = normalized
        }

        return segments
    }

    private func appendSegment(_ segment: String, to segments: inout [String]) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        segments.append(trimmed)
    }
}
