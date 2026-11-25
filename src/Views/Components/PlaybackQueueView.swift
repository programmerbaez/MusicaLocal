// Cola de reproducción de Música Local. SwiftUI compatible con macOS 12.
import SwiftUI

/// Acceso visible y autónomo por ventana. Cada botón controla su propio popover:
/// compartir un único Bool para tres popovers impedía asociarlo correctamente.
struct PlaybackQueueButton: View {
    @ObservedObject var player: Player
    @ObservedObject var accent: AccentModel
    var size: CGFloat = 14
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet")
                    .font(.system(size: size, weight: .semibold))
                Text("Cola")
                    .font(.system(size: 11, weight: .medium))
            }
            // El botón se mantiene neutro y legible sobre material translúcido.
            // El acento de la carátula se conserva dentro de la cola, en la pista activa.
            .foregroundColor(.primary)
            .padding(.horizontal, 7)
            .frame(height: 25)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isPresented ? 0.14 : 0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Abrir cola de reproducción")
        .accessibilityLabel("Cola de reproducción")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PlaybackQueueView(player: player, accent: accent)
        }
    }
}

struct PlaybackQueueView: View {
    @ObservedObject var player: Player
    @ObservedObject var accent: AccentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cola de reproducción").font(.headline)
                Spacer()
                if !player.upcomingQueue.isEmpty {
                    Button("Vaciar") { player.clearQueue() }
                        .font(.caption)
                }
            }
            if let current = player.nowPlaying {
                Text("REPRODUCIENDO").font(.caption2).foregroundColor(.secondary)
                queueRow(current, index: nil, current: true)
                Divider()
            }
            if !player.upcomingQueue.isEmpty {
                Text("AÑADIDAS MANUALMENTE").font(.caption2).foregroundColor(.secondary)
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(player.upcomingQueue.enumerated()), id: \.offset) { index, track in
                            queueRow(track, index: index, current: false)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            HStack {
                Text(player.shuffle ? "A CONTINUACIÓN · ALEATORIO" : "A CONTINUACIÓN · EN ORDEN")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                if player.shuffle { Image(systemName: "shuffle").foregroundColor(.secondary) }
            }
            if player.automaticUpcomingQueue.isEmpty {
                Text("No hay más canciones en la secuencia actual.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(player.automaticUpcomingQueue.enumerated()), id: \.offset) { _, track in
                            queueRow(track, index: nil, current: false)
                        }
                    }
                }
                .frame(maxHeight: 310)
            }
        }
        .padding(15)
        .frame(width: 370)
    }

    private func queueRow(_ track: Track, index: Int?, current: Bool) -> some View {
        HStack(spacing: 8) {
            if current {
                queueTrackLabel(track)
                Image(systemName: "waveform")
                    .foregroundColor(accent.shown.color)
                    .help("Reproduciendo ahora")
            } else {
                // Solo el contenido de la fila es un botón: los controles de
                // ordenar o eliminar siguen siendo botones independientes.
                Button {
                    if let index = index {
                        player.playQueued(at: index)
                    } else if let position = player.automaticUpcomingQueue.firstIndex(where: { $0.id == track.id }) {
                        player.playAutomaticQueued(at: position)
                    }
                } label: {
                    queueTrackLabel(track)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reproducir ahora: \(track.title)")
                .accessibilityLabel("Reproducir \(track.title)")

                if let index = index {
                    Button { player.playQueued(at: index) } label: {
                        Image(systemName: "play.fill")
                    }.help("Reproducir ahora")
                    Button { player.moveQueueItem(from: index, to: index - 1) } label: {
                        Image(systemName: "chevron.up")
                    }.disabled(index == 0).help("Subir")
                    Button { player.moveQueueItem(from: index, to: index + 1) } label: {
                        Image(systemName: "chevron.down")
                    }.disabled(index == player.upcomingQueue.count - 1).help("Bajar")
                    Button { player.removeFromQueue(at: index) } label: {
                        Image(systemName: "xmark")
                    }.help("Quitar de la cola")
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(current ? accent.shown.color.opacity(0.17) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if current {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent.shown.color)
                    .frame(width: 3)
            }
        }
    }

    private func queueTrackLabel(_ track: Track) -> some View {
        HStack(spacing: 8) {
            ArtworkView(url: track.url, size: 36, large: false, corner: 5)
                .id(track.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(track.artist.isEmpty ? "Artista desconocido" : track.artist)
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
