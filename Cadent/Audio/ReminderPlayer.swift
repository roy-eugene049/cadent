import AVFoundation
import Foundation

@MainActor
final class ReminderPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var lastError: String?
    private var player: AVAudioPlayer?
    var onChange: (() -> Void)?

    func play(url: URL) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else {
                lastError = "Cadent couldn't play this recording."
                isPlaying = false
                onChange?()
                Log.error("playback failed to start")
                return
            }
            self.player = player
            isPlaying = true
            lastError = nil
            onChange?()
            Log.info("playback started")
        } catch {
            isPlaying = false
            lastError = error.localizedDescription
            onChange?()
            Log.error("playback failed \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if isPlaying {
            isPlaying = false
            onChange?()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.isPlaying = false
            self.player = nil
            self.onChange?()
        }
    }
}
