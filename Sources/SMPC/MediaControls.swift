import Foundation
import MediaPlayer

@MainActor final class MediaControls {
    static let shared = MediaControls()
    private var installed = false
    private init() {}

    func install() {
        guard !installed else { return }
        installed = true
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.stopCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.playCommand.addTarget { _ in
            Task { @MainActor in PlayerStore.shared.perform("play", success: "Playing") }
            return .success
        }
        commands.pauseCommand.addTarget { _ in
            Task { @MainActor in PlayerStore.shared.perform("pause 1", success: "Paused") }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlayerStore.shared.playPause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerStore.shared.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlayerStore.shared.previous() }
            return .success
        }
        commands.stopCommand.addTarget { _ in
            Task { @MainActor in PlayerStore.shared.stopPlayback() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                let seconds = event.positionTime
                Task { @MainActor in PlayerStore.shared.seek(seconds) }
            }
            return .success
        }
        let center = MPNowPlayingInfoCenter.default()
        var initial = idleInfo
        // Claim Now Playing once so macOS routes media keys before the first play action.
        initial[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        center.nowPlayingInfo = initial
        center.playbackState = .playing
        initial[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        center.nowPlayingInfo = initial
        center.playbackState = .paused
    }

    func update(song: Song?, status: MPDStatus) {
        guard let song else { clearInfo(); return }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.displayTitle,
            MPMediaItemPropertyArtist: song.displayArtist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: status.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: status.elapsed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackRate: status.state == "play" ? 1.0 : 0.0
        ]
        center.playbackState = status.state == "play" ? .playing : .paused
    }

    private var idleInfo: [String: Any] {
        [MPMediaItemPropertyTitle: "MMM-UI",
         MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
         MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
         MPNowPlayingInfoPropertyPlaybackRate: 0.0]
    }

    func clearInfo() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = idleInfo
        center.playbackState = .paused
    }

    func clear() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }
}
