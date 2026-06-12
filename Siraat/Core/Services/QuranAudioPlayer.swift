import AVFoundation
import Foundation

@MainActor
final class QuranAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentVerseKey: String?
    @Published var isRepeatEnabled = false

    private var player: AVPlayer?
    private var queue: [QuranVerse] = []
    private var currentIndex = 0
    private var endObserver: NSObjectProtocol?

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
        if isRepeatEnabled {
            play()
        } else if currentIndex < queue.count - 1 {
            currentIndex += 1
            play()
        } else {
            isPlaying = false
        }
    }
}
