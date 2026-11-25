// Música Local — PlaybackModels
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Reloj de reproducción (separado para no redibujar la lista)

final class PlaybackClock: ObservableObject {
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    /// Amplitud normalizada del audio (0...1); no es un análisis FFT por bandas.
    @Published var audioLevel: Double = 0
}

enum RepeatMode: String, CaseIterable {
    case off, all, one

    var label: String {
        switch self {
        case .off: return "Desactivado"
        case .all: return "Repetir lista"
        case .one: return "Repetir canción"
        }
    }

    var icon: String { self == .one ? "repeat.1" : "repeat" }

    var cycled: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

struct ScrollRequest: Equatable {
    let id: String
    let center: Bool
    let nonce: Int
}

