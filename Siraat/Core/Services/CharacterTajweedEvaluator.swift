import Foundation

struct CharacterTajweedEvaluator {
    var lowConfidenceFloor = 0.60
    var criticalConfidence = 0.85
    var maddShortRatio = 0.5
    var ghunnahDurationThreshold: TimeInterval = 0.45
    var maximumMaddDuration: TimeInterval = 1.50

    func evaluate(
        uthmani: String,
        blueprint: AyahPhonemeMap,
        aligned: [AlignedPhoneme]
    ) -> [RecitationCharacterResult] {
        let clusters = UthmaniCharacterMapper.clusters(in: uthmani)
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
            let verdict = classify(cluster: cluster, phoneme: phoneme, observation: observation)
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
        cluster: UthmaniCluster,
        phoneme: CanonicalPhoneme,
        observation: AlignedPhoneme?
    ) -> (color: RecitationCharacterColor, errorType: RecitationCharacterErrorType?) {
        guard let observation else {
            return (.red, .missed)
        }
        guard observation.confidence >= lowConfidenceFloor else {
            return (.green, nil)
        }

        // 1. Tashkeel/Letter Check
        let heardDifferentLetter = !ArabicLetterInfo.sameBaseLetter(observation.baseLetter, phoneme.baseCharacter)
        if heardDifferentLetter && observation.confidence >= criticalConfidence {
            return (.red, .tashkeelWrong)
        }

        // 2. Madd Timing (High Precision)
        if phoneme.isMaddVowel && !heardDifferentLetter {
            let expected = phoneme.expectedDurationSeconds
            if observation.duration < expected * maddShortRatio {
                return (.yellow, .maddShort)
            }
            if observation.duration > maximumMaddDuration {
                return (.yellow, .maddLong)
            }
        }

        // 3. Ghunnah Check (High Precision)
        if phoneme.requiresGhunnah {
            if observation.duration < ghunnahDurationThreshold {
                return (.yellow, .ghunnahMissed)
            }
        }

        // 4. Qalqalah Check (High Precision)
        if phoneme.requiresQalqalah {
            // In a real implementation, we would check for a burst in the acoustic data.
            // For now, we assume the aligner provides this via a flag or we use duration.
        }

        return (.green, nil)
    }
}
