// Música Local — Formatting
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

enum AppVersion {
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    static var label: String {
        current.map { "Versión \($0)" } ?? "Versión desconocida"
    }
}

func fmt(_ t: Double) -> String {
    guard t.isFinite, t > 0 else { return "0:00" }
    let s = Int(t)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, sec)
        : String(format: "%d:%02d", m, sec)
}

func resignFocus() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

