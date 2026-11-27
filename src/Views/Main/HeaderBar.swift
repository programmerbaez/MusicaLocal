// Música Local — HeaderBar
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Barra superior

struct HeaderBar: View {
    @EnvironmentObject var p: Player
    @EnvironmentObject var mini: MiniPlayerController
    let accent: AccentModel
    let onCreatePlaylist: () -> Void
    let onRemoveUnavailableTrack: (String) -> Void
    @State private var showingPlaylists = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                WindowControls()
                UpdateMenuButton()
            }

            if p.folderURL != nil {
                Label("\(p.folderName) · \(p.tracks.count) \(p.tracks.count == 1 ? "canción" : "canciones")",
                      systemImage: "folder.fill")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            playlistButton

            if p.isScanning && p.metaTotal > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo metadatos \(p.metaDone)/\(p.metaTotal)")
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button { p.revealCurrent() } label: {
                Image(systemName: "scope").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .disabled(p.nowPlaying == nil)
            .help("Ir a la canción actual (⌘L)")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Buscar", text: $p.query)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        resignFocus()
                        p.selectFirstIfNeeded()
                    }
                if !p.query.isEmpty {
                    Button { p.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
            .frame(width: 210)

            PlaybackQueueButton(player: p, accent: accent, size: 15)

            Button { mini.show() } label: {
                Image(systemName: "pip.enter").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Abrir mini reproductor (⌥⌘M)")

            Button { openSettings() } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Ajustes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var playlistButton: some View {
        Button {
            showingPlaylists.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 15, weight: .semibold))
                Text(p.activePlaylist?.name ?? "Listas")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 110)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 7)
            .frame(height: 25)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(showingPlaylists ? 0.14 : 0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .help("Elegir biblioteca o lista de reproducción")
        .accessibilityLabel("Listas de reproducción")
        .accessibilityValue(p.activePlaylist?.name ?? "Biblioteca")
        .popover(isPresented: $showingPlaylists, arrowEdge: .bottom) {
            playlistPopover
        }
    }

    private var playlistPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Listas de reproducción").font(.headline)
                Spacer()
                Button("Nueva lista…") {
                    showingPlaylists = false
                    onCreatePlaylist()
                }
            }
            Divider()
            playlistOption("Biblioteca", id: nil)
            if !p.playlists.isEmpty || !p.unavailablePlaylistPaths.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(p.playlists) { playlist in
                            playlistOption(playlist.name, id: playlist.id)
                        }
                        if !p.unavailablePlaylistPaths.isEmpty {
                            Divider()
                            Text("Canciones fuera de la biblioteca")
                                .font(.caption).foregroundColor(.secondary)
                            ForEach(p.unavailablePlaylistPaths, id: \.self) { path in
                                Button {
                                    showingPlaylists = false
                                    onRemoveUnavailableTrack(path)
                                } label: {
                                    Label("Quitar \(URL(fileURLWithPath: path).lastPathComponent)",
                                          systemImage: "minus.circle")
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .help(path)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 325)
    }

    private func playlistOption(_ title: String, id: Playlist.ID?) -> some View {
        Button {
            p.selectPlaylist(id)
            showingPlaylists = false
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if p.activePlaylistID == id {
                    Image(systemName: "checkmark")
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// Aplica la barra de título extendida exclusivamente a la ventana principal.
/// Los tres botones nativos se ocultan: la interfaz ofrece controles equivalentes.
/// NSViewRepresentable permite acceder a la NSWindow real sin APIs de macOS 13+.
