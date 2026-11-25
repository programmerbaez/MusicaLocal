// Música Local — TrackRow
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Fila de canción

struct TrackRow: View {
    @Environment(\.colorScheme) private var scheme
    let track: Track
    let index: Int
    let cols: ColumnLayout
    let isCurrent: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let accent: AccentModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ArtworkView(url: track.url, size: 34, large: false, corner: 5)
                if isCurrent {
                    RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.45))
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 34, height: 34)

            Text(track.title)
                // El título conserva el color de texto normal; solo el fondo
                // y el indicador lateral adoptan el color de la carátula.
                .foregroundColor(scheme == .light ? AppearancePalette.charcoal : .primary)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cols.title, alignment: .leading)

            Text(track.artist.isEmpty ? "Artista desconocido" : track.artist)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cols.artist, alignment: .leading)

            Text(track.album.isEmpty ? "Álbum desconocido" : track.album)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cols.album, alignment: .leading)

            Text(track.duration > 0 ? fmt(track.duration) : "—")
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background {
            if isCurrent {
                CurrentTrackTint(accent: accent)
            } else if isSelected {
                Color.primary.opacity(0.09)
            } else if index % 2 == 0 {
                Color.primary.opacity(0.04)
            }
        }
        .overlay(alignment: .leading) {
            if isCurrent { CurrentTrackLeadingLine(accent: accent) }
        }
        .contentShape(Rectangle())
    }

}

private struct CurrentTrackTint: View {
    @ObservedObject var accent: AccentModel

    var body: some View {
        accent.shown.color.opacity(0.16)
    }
}

private struct CurrentTrackLeadingLine: View {
    @ObservedObject var accent: AccentModel

    var body: some View {
        Rectangle().fill(accent.shown.color).frame(width: 3)
    }
}
