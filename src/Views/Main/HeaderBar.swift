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

    var body: some View {
        HStack(spacing: 12) {
            WindowControls()

            if p.folderURL != nil {
                Label("\(p.folderName) · \(p.tracks.count) \(p.tracks.count == 1 ? "canción" : "canciones")",
                      systemImage: "folder.fill")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if p.isScanning && p.metaTotal > 0 {
                ProgressView().controlSize(.small)
                Text("Leyendo metadatos \(p.metaDone)/\(p.metaTotal)")
                    .font(.caption).foregroundColor(.secondary)
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
}

/// Aplica la barra de título extendida exclusivamente a la ventana principal.
/// Los tres botones nativos se ocultan: la interfaz ofrece controles equivalentes.
/// NSViewRepresentable permite acceder a la NSWindow real sin APIs de macOS 13+.
