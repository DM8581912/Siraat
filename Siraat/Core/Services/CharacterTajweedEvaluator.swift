import Foundation

/// Turns timestamped phonemes + a canonical blueprint into per-character feedback.
///
/// Honesty is enforced here: when the aligner's confidence for a phoneme is low, the
/// cluster stays green. On-device acoustic models mis-hear classical Arabic, and telling
/// a correct reciter they erred is a trust failure in a worship app. We flag only what we
/// are confident about.
struct CharacterTajweedEvaluator {
    /// Below this confidence we do not flag anything — stay green.
    var lowConfidenceFloor = 0.60
    /// At or above this confidence a detected substitution is a strict (red) error.
    var criticalConfidence = 0.85
    /// A Madd shorter than `expected * maddShortRatio` is flagged as cut short.
    var maddShortRatio = 0.5
    /// A Ghunnah nasal shorter than this (and below ~2 harakāt when measured) is flagged.
    var ghunnahDurationThreshold: TimeInterval = 0.45
    var maximumMaddDuration: TimeInterval = 1.50

    /// One result per base-letter cluster of `uthmani`, aligned to the blueprint's
    /// phonemes (and the aligner's output) by reading order.
    func evaluate(
        uthmani: String,
        blueprint: AyahPhonemeMap,
        alignment: ForcedAlignment
    ) -> [RecitationCharacterResult] {
        let clusters = UthmaniCharacterMapper.clusters(in: uthmani)
        let aligned = alignment.phonemes

        return clusters.enumerated().map { index, cluster in
            guard index < blueprint.phonemes.count else {
                return RecitationCharacterResult(
                    char: cluster.text,
                    color: .green,
                    errorType: nil,
                    duration: 0,
                    utf16Range: cluster.utf16Range
                )
            }

            let phoneme = blueprint.phonemes[index]
            let observation = index < aligned.count ? aligned[index] : nil
            let verdict = classify(
                phoneme: phoneme,
                observation: observation,
                harakatSeconds: alignment.harakatSeconds
            )

            return RecitationCharacterResult(
                char: cluster.text,
                color: verdict.color,
                errorType: verdict.errorType,
                duration: observation?.duration ?? 0,
                utf16Range: cluster.utf16Range
            )
        }
    }

    private func classify(
        phoneme: CanonicalPhoneme,
        observation: AlignedPhoneme?,
        harakatSeconds: Double?
    ) -> (color: RecitationCharacterColor, errorType: RecitationCharacterErrorType?) {
        // 1. The phoneme was not heard at all — a strict miss.
        guard let observation else {
            return (.red, .missed)
        }

        // 2. Too uncertain to judge — honesty: do not flag. (Consonants we do not yet grade
        //    acoustically are emitted below this floor by the aligner, so they stay green.)
        guard observation.confidence >= lowConfidenceFloor else {
            return (.green, nil)
        }

        // 3. Confident, but the recognizer heard a different letter/vowel than expected.
        let heardDifferentLetter = !ArabicLetterInfo.sameBaseLetter(observation.baseLetter, phoneme.baseCharacter)
        if heardDifferentLetter && observation.confidence >= criticalConfidence {
            return (.red, .tashkeelWrong)
        }

        // 4. Madd timing. Prefer the reciter's own measured harakah (tempo-invariant): a
        //    natural Madd should run at least ~2 harakāt, so flag below ~1 harakah. Fall
        //    back to the blueprint's reference duration when no harakah unit was measured.
        if phoneme.isMaddVowel && !heardDifferentLetter {
            let expected = harakatSeconds.map { $0 * 2 } ?? phoneme.expectedDurationSeconds
            let longBound = harakatSeconds.map { $0 * 6 } ?? maximumMaddDuration
            if expected > 0 && observation.duration < expected * maddShortRatio {
                return (.yellow, .maddShort)
            }
            if observation.duration > longBound {
                return (.yellow, .maddLong)
            }
        }

        // 5. Ghunnah: a nasal (نّ / مّ / tanwīn) must be held ~2 harakāt. Uses the measured
        //    harakah when available, else a fixed threshold. Only evaluated when the aligner
        //    confidently measured this nasal (confidence >= floor).
        if phoneme.requiresGhunnah && !heardDifferentLetter {
            let minimumGhunnah = harakatSeconds.map { $0 * 2 } ?? ghunnahDurationThreshold
            if observation.duration < minimumGhunnah * maddShortRatio {
                return (.yellow, .ghunnahMissed)
            }
        }

        // 6. Qalqalah (echo on ق ط ب ج د with sukūn) needs a plosive-burst signal from the
        //    acoustic layer; duration alone is not a reliable proxy, so it is left for a
        //    future acoustic feature rather than risking a false verdict.

        return (.green, nil)
    }
}
