// Música Local — PlayerBar
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Barra de reproducción

struct PlayerBar: View {
    @AppStorage("visualizerStyle") private var visualizerStyleRaw = VisualizerStyle.bars.rawValue
    @ObservedObject var p: Player
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var accent: AccentModel
    @Binding var showingLyrics: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                nowPlayingInfo.frame(maxWidth: .infinity, alignment: .leading)
                transport
                volumeControl
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text(fmt(clock.progress))
                    .font(.caption).monospacedDigit().foregroundColor(.secondary)
                    .frame(width: 46, alignment: .trailing)
                Slider(
                    value: $clock.progress,
                    in: 0...max(clock.duration, 1),
                    onEditingChanged: { editing in
                        p.isSeeking = editing
                        if !editing { p.seek(clock.progress) }
                    }
                )
                .disabled(p.nowPlaying == nil)
                .tint(accent.shown.color)
                Text(fmt(clock.duration))
                    .font(.caption).monospacedDigit().foregroundColor(.secondary)
                    .frame(width: 46, alignment: .leading)
            }
            if visualizerStyleRaw != VisualizerStyle.off.rawValue {
                AudioLevelVisualizer(clock: clock, tint: accent.shown.color)
                    .frame(height: 21)
                    .padding(.horizontal, 54)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035))
    }

    private var nowPlayingInfo: some View {
        HStack(spacing: 12) {
            ArtworkView(url: p.nowPlaying?.url, size: 54, large: true, corner: 8)
                .id(p.nowPlaying?.id)  // Reinicia el estado visual en cada cambio de pista.
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(p.nowPlaying?.title ?? "Nada en reproducción")
                    .font(.headline)
                    .lineLimit(1)
                Text(p.nowPlaying?.album.isEmpty == false ? (p.nowPlaying?.album ?? "") : "Álbum desconocido")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(p.nowPlaying?.artist.isEmpty == false ? (p.nowPlaying?.artist ?? "") : "Artista desconocido")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { p.revealCurrent() }
        .help("Mostrar en la lista")
    }

    private var transport: some View {
        HStack(spacing: 22) {
            Button { p.shuffle.toggle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(p.shuffle ? accent.shown.color : .secondary)
            }
            .help(p.shuffle ? "Aleatorio: activado" : "Aleatorio: desactivado")

            Button { p.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 18))
            }
            Button { p.togglePlay() } label: {
                Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
            }
            Button { p.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 18))
            }

            Button { p.repeatMode = p.repeatMode.cycled } label: {
                Image(systemName: p.repeatMode.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(p.repeatMode == .off ? .secondary : accent.shown.color)
            }
            .help("Repetir: \(p.repeatMode.label)")
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button { showingLyrics.toggle() } label: {
                Image(systemName: showingLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .foregroundColor(showingLyrics ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(p.nowPlaying == nil)
            .help(showingLyrics ? "Ocultar letras" : "Mostrar letras")
            .accessibilityLabel(showingLyrics ? "Ocultar letras" : "Mostrar letras")
            PlaybackQueueButton(player: p, accent: accent)
            Button { p.toggleMute() } label: {
                Image(systemName: volumeIcon)
                    .foregroundColor(.secondary)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help(p.volume > 0.01 ? "Silenciar" : "Activar sonido")

            Slider(value: $p.volume, in: 0...1)
                .tint(accent.shown.color)
                .frame(width: 110)
        }
    }

    private var volumeIcon: String {
        switch p.volume {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }
}

