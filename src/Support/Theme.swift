// Música Local — Theme
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Tema (claro / oscuro / sistema)

/// Fundido suave entre apariencias: congela una captura de cada ventana, cambia el tema
/// y desvanece la captura. Evita el "salto" instantáneo de AppKit al cambiar `NSApp.appearance`.
enum ThemeTransition {
    private final class PassthroughImageView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    static func run(_ change: () -> Void) {
        var overlays: [NSView] = []
        for win in NSApp.windows where win.isVisible && !(win is NSPanel) {
            guard let content = win.contentView else { continue }
            let b = content.bounds
            guard b.width > 1, b.height > 1,
                  let rep = content.bitmapImageRepForCachingDisplay(in: b) else { continue }
            content.cacheDisplay(in: b, to: rep)
            let snapshot = NSImage(size: b.size)
            snapshot.addRepresentation(rep)

            let iv = PassthroughImageView(frame: b)
            iv.image = snapshot
            iv.imageScaling = .scaleAxesIndependently
            iv.autoresizingMask = [.width, .height]
            iv.wantsLayer = true
            content.addSubview(iv, positioned: .above, relativeTo: nil)
            overlays.append(iv)
        }

        change()
        guard !overlays.isEmpty else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for v in overlays { v.animator().alphaValue = 0 }
        }, completionHandler: {
            for v in overlays { v.removeFromSuperview() }
        })
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    private static var applied: AppTheme?

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistema"
        case .light:  return "Claro"
        case .dark:   return "Oscuro"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// Aplica el tema. Es idempotente: llamarlo dos veces con el mismo valor no hace nada.
    func apply(animated: Bool) {
        if AppTheme.applied == self { return }
        let isFirst = AppTheme.applied == nil
        AppTheme.applied = self
        if animated && !isFirst {
            ThemeTransition.run { self.setAppearance() }
        } else {
            setAppearance()
        }
    }

    private func setAppearance() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

