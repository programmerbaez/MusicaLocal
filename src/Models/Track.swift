// Música Local — Track
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Modelo de canción

enum SortKey { case title, artist, album, duration }

struct Track: Identifiable, Hashable {
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var mtime: Double
    var loaded: Bool

    var id: String { url.path }

    static func == (l: Track, r: Track) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

