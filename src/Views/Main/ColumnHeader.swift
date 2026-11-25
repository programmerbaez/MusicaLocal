// Música Local — ColumnHeader
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Cabecera de columnas

struct ColumnHeader: View {
    @EnvironmentObject var p: Player
    let cols: ColumnLayout

    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 34, height: 1)
            sortButton("Título", .title).frame(width: cols.title, alignment: .leading)
            sortButton("Artista", .artist).frame(width: cols.artist, alignment: .leading)
            sortButton("Álbum", .album).frame(width: cols.album, alignment: .leading)
            sortButton("Duración", .duration).frame(width: 80, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func sortButton(_ title: String, _ key: SortKey) -> some View {
        Button { p.toggleSort(key) } label: {
            HStack(spacing: 4) {
                Text(title)
                if p.sortKey == key {
                    Image(systemName: p.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

