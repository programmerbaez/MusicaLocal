// Música Local — NowPlayingBridge
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Integración con macOS (Centro de Control, teclas multimedia, auriculares)

private func makeMPArtwork(_ image: NSImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
}

final class NowPlayingBridge {
    private weak var player: Player?
    private var artworkID: String?
    private var artwork: MPMediaItemArtwork?
    private var artToken: ArtworkStore.Token = 0
    private var scheduled = false

    init(player: Player) {
        self.player = player
        setupCommands()
    }

    private func run(_ work: @escaping (Player) -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let p = self?.player { work(p) }
        }
    }

    private func setupCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.isEnabled = true
        c.pauseCommand.isEnabled = true
        c.togglePlayPauseCommand.isEnabled = true
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
        c.changePlaybackPositionCommand.isEnabled = true

        c.playCommand.addTarget { [weak self] _ in
            self?.run { $0.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.run { $0.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.run { $0.togglePlay() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.run { $0.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.run { $0.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            self?.run { $0.seek(t) }
            return .success
        }
    }

    /// Agrupa varias peticiones de actualización en una sola por ciclo del run loop.
    func scheduleRefresh() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.scheduled = false
            self?.refresh()
        }
    }

    private func refresh() {
        guard let p = player else { return }
        let center = MPNowPlayingInfoCenter.default()

        guard let t = p.nowPlaying else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            artworkID = nil
            artwork = nil
            ArtworkStore.shared.cancel(artToken)
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyPlaybackDuration: p.clock.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: p.currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: p.isPlaying ? 1.0 : 0.0
        ]
        if !t.artist.isEmpty { info[MPMediaItemPropertyArtist] = t.artist }
        if !t.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = t.album }
        if artworkID == t.id, let art = artwork { info[MPMediaItemPropertyArtwork] = art }

        center.nowPlayingInfo = info
        center.playbackState = p.isPlaying ? .playing : .paused

        if artworkID != t.id {
            artworkID = t.id
            artwork = nil
            ArtworkStore.shared.cancel(artToken)
            let id = t.id
            artToken = ArtworkStore.shared.request(url: t.url, large: true) { [weak self] img in
                guard let self = self, self.artworkID == id, let img = img else { return }
                self.artwork = makeMPArtwork(img)
                self.scheduleRefresh()
            }
        }
    }
}

