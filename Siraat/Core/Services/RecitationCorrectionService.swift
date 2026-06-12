import Foundation

protocol RecitationCorrectionServicing {
    func prepareWords(for verse: QuranVerse, script: QuranScript) -> [RecitationWord]
    func evaluate(transcript: String, expectedWords: [RecitationWord]) -> [RecitationWord]
}

final class RecitationCorrectionService: RecitationCorrectionServicing {
    func prepareWords(for verse: QuranVerse, script: QuranScript) -> [RecitationWord] {
        verse.text(for: script)
            .split(separator: " ")
            .map { RecitationWord(originalText: String($0)) }
    }

    func evaluate(transcript: String, expectedWords: [RecitationWord]) -> [RecitationWord] {
        let spokenTokens = ArabicTextNormalizer.tokens(from: transcript)
        guard !spokenTokens.isEmpty else { return expectedWords }

        return expectedWords.enumerated().map { index, word in
            var evaluated = word
            evaluated.tajweedViolations = []
            let expected = ArabicTextNormalizer.tokens(from: word.originalText).first ?? ""

            guard index < spokenTokens.count else {
                evaluated.status = .pending
                evaluated.tip = nil
                return evaluated
            }

            let spoken = spokenTokens[index]
            if spoken == expected {
                evaluated.status = .correct
                evaluated.tip = nil
            } else if expected.hasPrefix(spoken) || spoken.hasPrefix(expected) || levenshtein(spoken, expected) <= 1 {
                evaluated.status = .uncertain
                evaluated.tip = CorrectionTip(
                    title: "Keep going",
                    message: "We heard something close to \(word.originalText). Advisory Tajweed feedback is processed on-device — recite at your own pace."
                )
            } else {
                // Deliberately NOT a "wrong" verdict. On-device speech recognition mis-hears
                // classical Quranic Arabic frequently, so a mismatch here is at least as
                // likely a recognizer slip as a recitation error. Telling a correct reciter
                // they erred is a trust failure in a religious app — stay neutral. Real
                // tajweed evaluation is the job of the acoustic model behind
                // RecitationAnalysisProviding, not this text matcher.
                evaluated.status = .pending
                evaluated.tip = nil
            }

            return evaluated
        }
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: rhs.count + 1), count: lhs.count + 1)

        for index in 0...lhs.count { matrix[index][0] = index }
        for index in 0...rhs.count { matrix[0][index] = index }

        for leftIndex in 1...lhs.count {
            for rightIndex in 1...rhs.count {
                let cost = lhs[leftIndex - 1] == rhs[rightIndex - 1] ? 0 : 1
                matrix[leftIndex][rightIndex] = min(
                    matrix[leftIndex - 1][rightIndex] + 1,
                    matrix[leftIndex][rightIndex - 1] + 1,
                    matrix[leftIndex - 1][rightIndex - 1] + cost
                )
            }
        }

        return matrix[lhs.count][rhs.count]
    }
}
