// Música Local — MiniPlayerController
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Mini reproductor flotante (macOS 12+)

/// Dos presentaciones para un único NSPanel. El audio, el reloj y la carátula
/// proceden de las mismas instancias usadas por la ventana principal.
final class MiniPlayerController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var expanded: Bool = UserDefaults.standard.bool(forKey: "miniExpanded") {
        didSet {
            UserDefaults.standard.set(expanded, forKey: "miniExpanded")
            updateSize(animated: true)
        }
    }
    @Published var alwaysOnTop: Bool = UserDefaults.standard.bool(forKey: "miniAlwaysOnTop") {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: "miniAlwaysOnTop")
            panel?.level = alwaysOnTop ? .floating : .normal
        }
    }

    private var panel: NSPanel?
    private weak var mainWindow: NSWindow?
    private var returningToMain = false
    private weak var player: Player?
    private weak var accent: AccentModel?

    private var targetSize: NSSize {
        expanded ? NSSize(width: 520, height: 334) : NSSize(width: 410, height: 178)
    }

    func configure(player: Player, accent: AccentModel) {
        self.player = player
        self.accent = accent
    }

    func show() {
        guard let player = player, let accent = accent else { return }
        if let existing = panel {
            NSApp.activate(ignoringOtherApps: true)
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Mantener la referencia a la ventana base sin destruir su SwiftUI state.
        if let window = NSApp.keyWindow, !(window is NSPanel), window.title == "Música Local" {
            mainWindow = window
        } else if let window = NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.title == "Música Local"
        }) {
            mainWindow = window
        }

        let size = targetSize
        let win = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        win.title = "Mini reproductor"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        // Controles dibujados dentro de SwiftUI, sin semáforos nativos duplicados.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            win.standardWindowButton(kind)?.isHidden = true
        }
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = alwaysOnTop ? .floating : .normal
        win.delegate = self
        win.minSize = size
        win.maxSize = size

        let view = MiniPlayerView(player: player, clock: player.clock,
                                  accent: accent, controller: self)
            .appAccent(accent)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        win.contentView = hosting
        // La superficie del NSPanel también recorta sus cuatro esquinas.
        // Esto evita las esquinas inferiores cuadradas del marco de AppKit.
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 22
        hosting.layer?.masksToBounds = true
        win.hasShadow = true

        // Colocarlo cerca de la esquina superior derecha de la pantalla visible.
        if let screen = mainWindow?.screen ?? NSScreen.main {
            let rect = screen.visibleFrame
            win.setFrameOrigin(NSPoint(x: rect.maxX - size.width - 24,
                                       y: rect.maxY - size.height - 24))
        } else {
            win.center()
        }
        panel = win
        mainWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if panel != nil { returnToMain() } else { show() }
    }

    func minimizePanel() {
        panel?.miniaturize(nil)
    }

    func returnToMain() {
        returningToMain = true
        if let win = panel {
            win.delegate = nil
            win.close()
            panel = nil
        }
        restoreMain()
        returningToMain = false
    }

    private func restoreMain() {
        let win = mainWindow ?? NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.title == "Música Local"
        })
        if let win = win {
            if win.isMiniaturized { win.deminiaturize(nil) }
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard !returningToMain else { return }
        panel = nil
        restoreMain()
    }

    private func updateSize(animated: Bool) {
        guard let win = panel else { return }
        let size = targetSize
        var frame = win.frame
        // Fijar el borde superior para que la tarjeta crezca hacia abajo.
        frame.origin.y += frame.height - size.height
        frame.size = size
        win.minSize = NSSize(width: 1, height: 1)
        win.maxSize = NSSize(width: 10000, height: 10000)
        win.setFrame(frame, display: true, animate: animated)
        win.minSize = size
        win.maxSize = size
    }
}

/// NSVisualEffectView sigue automáticamente la apariencia clara/oscura en Monterey.
