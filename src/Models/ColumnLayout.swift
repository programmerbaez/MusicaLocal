// Música Local — ColumnLayout
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Anchos de columna (Título y Artista pesan más que Álbum)

struct ColumnLayout: Equatable {
    var title: CGFloat
    var artist: CGFloat
    var album: CGFloat

    init(total: CGFloat) {
        // márgenes (32) + carátula (34) + duración (80) + 4 separaciones (48) + margen para la barra de scroll
        let fixed: CGFloat = 32 + 34 + 80 + 48 + 18
        let avail = max(total - fixed, 180)
        title = floor(avail * 4 / 9)
        artist = floor(avail * 3 / 9)
        album = floor(avail * 2 / 9)
    }
}

