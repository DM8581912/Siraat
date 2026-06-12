import AVFoundation
import Foundation
import Speech

enum AudioStreamError: LocalizedError {
    case speechUnavailable
    case microphoneDenied
    case speechDenied
    case recognitionRequestUnavailable

    var errorDescription: String? {
        switch self {
        case .speechUnavailable:
            "Speech recognition is not available for this language right now."
        case .microphoneDenied:
            "Microphone access is required to listen."
        case .speechDenied:
            "Speech recognition permission is required to transcribe Arabic audio."
        case .recognitionRequestUnavailable:
            "The speech recognition request could not be created."
        }
    }
}

@MainActor
final class AudioStreamManager: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var latestSegment: SpeechTranscriptSegment?
    @Published private(set) var isRecording = false
    @Published private(set) var waveformLevel: Double = 0
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        let allowed = speechStatus == .authorized && microphoneGranted

        if !allowed {
            errorMessage = speechStatus == .authorized ? AudioStreamError.microphoneDenied.localizedDescription : AudioStreamError.speechDenied.localizedDescription
        }

        return allowed
    }

    func start(languageIdentifier: String = "ar-SA") async throws {
        guard await requestPermissions() else { return }

        stop()

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageIdentifier))
        guard let recognizer, recognizer.isAvailable else {
            throw AudioStreamError.speechUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request
        transcript = ""
        latestSegment = nil

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.level(from: buffer)
            Task { @MainActor in
                self?.waveformLevel = level
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    self.latestSegment = SpeechTranscriptSegment(text: text, isFinal: result.isFinal)
                }

                if let error {
                    self.errorMessage = error.localizedDescription
                    self.stop()
                }
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        waveformLevel = 0
    }

    nonisolated private static func level(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameLength {
            sum += channelData[index] * channelData[index]
        }

        let rms = sqrt(sum / Float(frameLength))
        return min(max(Double(rms) * 18, 0), 1)
    }
}
