// Música Local — MiniPlayerView
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

struct MiniVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct MiniPlayerView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("visualizerStyle") private var visualizerStyleRaw = VisualizerStyle.bars.rawValue
    @ObservedObject var player: Player
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var accent: AccentModel
    @ObservedObject var controller: MiniPlayerController
    @State private var showQueueFromMenu = false

    var body: some View {
        VStack(spacing: 0) {
            // Controles de ventana en la esquina superior izquierda del panel,
            // separados de la carátula para no tapar la imagen del álbum.
            HStack(spacing: 8) {
                WindowControls(mini: controller)
                Spacer(minLength: 0)
                PlaybackQueueButton(player: player, accent: accent)
                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Abrir Configuración")
                .accessibilityLabel("Abrir Configuración")
                toggleSizeButton
                Button { controller.returnToMain() } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Volver al reproductor")
                returnButton
            }
            .padding(.horizontal, controller.expanded ? 15 : 12)
            .frame(height: 25)
            .padding(.top, 5)

            ZStack(alignment: .top) {
                if controller.expanded {
                    expandedBody.transition(.opacity)
                } else {
                    compactBody.transition(.opacity)
                }
            }
        }
        .foregroundColor(scheme == .light ? AppearancePalette.charcoal : .primary)
        .background(AppearanceSurface())
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(7)
        .symbolRenderingMode(.hierarchical)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: controller.expanded)
    }

    private var compactBody: some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                cover(78)
                VStack(alignment: .leading, spacing: 8) {
                    compactSongText
                    HStack(spacing: 10) {
                        transport
                        Spacer(minLength: 0)
                        volumeControls(compact: true)
                    }
                }
            }
            if visualizerStyleRaw != VisualizerStyle.off.rawValue {
                AudioLevelVisualizer(clock: clock, tint: accent.shown.color)
                    .frame(height: 18)
                    .padding(.horizontal, 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // Solo el reloj observa los cambios frecuentes de progreso.
    // El modo compacto no muestra barra: tiempo actual / duración junto al título.
    private var compactSongText: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(player.nowPlaying?.title ?? "Nada en reproducción")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                CompactPlaybackTime(clock: clock)
            }
            Text(player.nowPlaying?.album.isEmpty == false ? (player.nowPlaying?.album ?? "") : "Álbum desconocido")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(player.nowPlaying?.artist.isEmpty == false ? (player.nowPlaying?.artist ?? "") : "Artista desconocido")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var expandedBody: some View {
        HStack(spacing: 18) {
            cover(218)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("REPRODUCIENDO")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.4).foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                songText
                MiniProgress(player: player, clock: clock, showTimes: true)
                HStack {
                    Spacer()
                    transport
                    Spacer()
                }
                volumeControls(compact: false)
                if visualizerStyleRaw != VisualizerStyle.off.rawValue {
                    AudioLevelVisualizer(clock: clock, tint: accent.shown.color)
                        .frame(height: 23)
                }
            }
        }
        .padding(15)
    }

    private func volumeControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 9) {
            Button { player.toggleMute() } label: {
                Image(systemName: player.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: compact ? 11 : 13))
            }
            .buttonStyle(.plain)
            .help("Silenciar / activar sonido")
            Slider(value: $player.volume, in: 0...1)
                .tint(accent.shown.color)
                .frame(width: compact ? 78 : nil)
                .accessibilityLabel("Volumen")
        }
    }

    private var songText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(player.nowPlaying?.title ?? "Nada en reproducción")
                .font(.system(size: controller.expanded ? 16 : 13, weight: .semibold))
                .lineLimit(1)
            Text(player.nowPlaying?.album.isEmpty == false ? (player.nowPlaying?.album ?? "") : "Álbum desconocido")
                .font(.system(size: controller.expanded ? 12 : 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(player.nowPlaying?.artist.isEmpty == false ? (player.nowPlaying?.artist ?? "") : "Artista desconocido")
                .font(.system(size: controller.expanded ? 12 : 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func cover(_ size: CGFloat) -> some View {
        ArtworkView(url: player.nowPlaying?.url, size: size, large: true, corner: 12)
            .id(player.nowPlaying?.id)
            .shadow(color: .black.opacity(0.2), radius: 7, x: 0, y: 3)
    }

    private var transport: some View {
        HStack(spacing: controller.expanded ? 26 : 16) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: controller.expanded ? 19 : 15))
            }
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: controller.expanded ? 38 : 29))
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: controller.expanded ? 19 : 15))
            }
        }
        .buttonStyle(.plain)
        .disabled(player.nowPlaying == nil && player.tracks.isEmpty)
    }

    private var toggleSizeButton: some View {
        Button { controller.expanded.toggle() } label: {
            Image(systemName: controller.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(controller.expanded ? "Vista compacta" : "Vista ampliada")
    }

    private var returnButton: some View {
        Menu {
            Button("Cola de reproducción") { showQueueFromMenu = true }
            Divider()
            Button("Volver al reproductor") { controller.returnToMain() }
            Button(controller.expanded ? "Vista compacta" : "Vista ampliada") { controller.expanded.toggle() }
            Divider()
            Toggle("Mantener encima de otras ventanas", isOn: $controller.alwaysOnTop)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Opciones del mini reproductor")
        .popover(isPresented: $showQueueFromMenu, arrowEdge: .bottom) {
            PlaybackQueueView(player: player, accent: accent)
        }
    }
}

/// El progreso observa exclusivamente PlaybackClock, sin refrescar la lista.

/// Solo se actualiza cuando cambia PlaybackClock, sin modificar la lógica de audio.
private struct CompactPlaybackTime: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        Text("\(fmt(clock.progress))/\(fmt(clock.duration))")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Tiempo transcurrido y duración")
    }
}
