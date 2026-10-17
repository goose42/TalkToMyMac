import AVFoundation
import Observation

/// Plays back one saved recording on the transcript detail screen.
@MainActor
@Observable
final class RecordingPlayer: NSObject, AVAudioPlayerDelegate {
    /// Whether a recording is loaded; false if there's none on disk or it couldn't be opened.
    private(set) var isAvailable = false
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?

    /// Not observed — `AVAudioPlayer` doesn't publish it — so views re-read it on a timeline
    /// while playing.
    var currentTime: TimeInterval {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }

    /// Stops anything playing and loads the recording at `url`, if there is one. Reloading
    /// the recording that's already loaded keeps its place, unless the file has gone.
    func load(_ url: URL?) {
        if let url, url == player?.url, FileManager.default.fileExists(atPath: url.path) { return }
        stop()
        player = url.flatMap { try? AVAudioPlayer(contentsOf: $0) }
        player?.delegate = self
        player?.prepareToPlay()
        isAvailable = player != nil
        duration = player?.duration ?? 0
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying = player.isPlaying
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.player?.currentTime = 0
        }
    }
}
