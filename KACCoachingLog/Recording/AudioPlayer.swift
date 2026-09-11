import AVFoundation
import Foundation
import Observation

/// Simple playback for reviewing a recorded session.
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var loadedURL: URL?

    @ObservationIgnored private var player: AVAudioPlayer?

    func load(_ url: URL) {
        guard loadedURL != url else { return }
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        loadedURL = url
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    /// Polled by the UI through TimelineView.
    func currentTime() -> TimeInterval {
        guard let player else { return 0 }
        if isPlaying && !player.isPlaying {
            // Reached the end
            DispatchQueue.main.async { self.isPlaying = false }
        }
        return player.currentTime
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime() + seconds)
    }
}
