import Foundation

struct TranscriptSegmenter {
    private var emittedCharacterCount = 0
    private let delimiters = CharacterSet(charactersIn: ".!?؟۔\n")

    mutating func reset() {
        emittedCharacterCount = 0
    }

    mutating func consume(_ text: String, isFinal: Bool) -> [String] {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return [] }

        if normalizedText.count < emittedCharacterCount {
            emittedCharacterCount = 0
        }

        let searchStart = normalizedText.index(normalizedText.startIndex, offsetBy: min(emittedCharacterCount, normalizedText.count))
        var segments: [String] = []
        var segmentStart = searchStart
        var cursor = searchStart

        while cursor < normalizedText.endIndex {
            let scalar = normalizedText[cursor].unicodeScalars.first
            if let scalar, delimiters.contains(scalar) {
                let end = normalizedText.index(after: cursor)
                appendSegment(String(normalizedText[segmentStart..<end]), to: &segments)
                segmentStart = end
                emittedCharacterCount = normalizedText.distance(from: normalizedText.startIndex, to: end)
            }
            cursor = normalizedText.index(after: cursor)
        }

        if isFinal, segmentStart < normalizedText.endIndex {
            appendSegment(String(normalizedText[segmentStart..<normalizedText.endIndex]), to: &segments)
            emittedCharacterCount = normalizedText.count
        }

        return segments
    }

    private func appendSegment(_ segment: String, to segments: inout [String]) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        segments.append(trimmed)
    }
}
