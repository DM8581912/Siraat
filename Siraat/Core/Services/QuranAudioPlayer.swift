import AVFoundation
import Foundation

@MainActor
final class QuranAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentVerseKey: String?
    @Published var isRepeatEnabled = false
    /// Loop a contiguous range of queue indices (memorization). nil = no range loop.
    @Published var repeatRange: ClosedRange<Int>?

    private var player: AVPlayer?
    private var queue: [QuranVerse] = []
    private var currentIndex = 0
    private var endObserver: NSObjectProtocol?

    /// Pure decision for what plays after the current item finishes. Extracted so the
    /// playback logic is unit-testable (AVPlayer itself isn't). Returns nil to stop.
    nonisolated static func nextIndex(
        current: Int,
        queueCount: Int,
        repeatSingle: Bool,
        repeatRange: ClosedRange<Int>?
    ) -> Int? {
        guard queueCount > 0 else { return nil }
        if repeatSingle { return current }
        if let range = repeatRange {
            return current >= range.upperBound ? range.lowerBound : min(current + 1, queueCount - 1)
        }
        return current < queueCount - 1 ? current + 1 : nil
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func load(_ verses: [QuranVerse]) {
        queue = verses
        currentIndex = 0
        currentVerseKey = verses.first?.verseKey
    }

    func play(verse: QuranVerse? = nil) {
        if let verse, let index = queue.firstIndex(where: { $0.verseKey == verse.verseKey }) {
            currentIndex = index
        }

        guard queue.indices.contains(currentIndex), let url = queue[currentIndex].audioURL else {
            isPlaying = false
            currentVerseKey = queue.indices.contains(currentIndex) ? queue[currentIndex].verseKey : nil
            return
        }

        // Ensure the shared session is in a playback category. A prior recording
        // session (Live Translation / Recitation) leaves it in .record, which would
        // silently mute this playback.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)

        // Observe end-of-play for THIS item only. Observing with object: nil fired
        // handlePlaybackEnded() for any AVPlayerItem in the process, spuriously
        // advancing the queue.
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackEnded() }
        }

        currentVerseKey = queue[currentIndex].verseKey
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func next() {
        guard !queue.isEmpty else { return }
        currentIndex = min(currentIndex + 1, queue.count - 1)
        play()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        currentIndex = max(currentIndex - 1, 0)
        play()
    }

    private func handlePlaybackEnded() {
        guard let next = Self.nextIndex(
            current: currentIndex,
            queueCount: queue.count,
            repeatSingle: isRepeatEnabled,
            repeatRange: repeatRange
        ) else {
            isPlaying = false
            return
        }
        currentIndex = next
        play()
    }
}
