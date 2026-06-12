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

    override init() {
        super.init()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackEnded() }
        }
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

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
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
