// Música Local — WindowChrome
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

struct MainWindowChrome: NSViewRepresentable {
    let player: Player
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window = window, !(window is NSPanel), window.title == "Música Local" else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // El contenido SwiftUI proporciona la translucidez y el gradiente.
        // La ventana debe permitir que se vea el material bajo el contenido.
        window.isOpaque = false
        window.backgroundColor = .clear
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
    }
}

/// Semáforos estilo macOS dentro de la app, reutilizados en las tres vistas.
/// En el mini reproductor el botón verde alterna tarjeta/barra.
struct WindowControls: View {
    var mini: MiniPlayerController? = nil

    private enum Kind: String { case close, minimize, zoom }
    @State private var hovered: Kind?

    var body: some View {
        HStack(spacing: mini == nil ? 8 : 5) {
            button(.close, color: Color(red: 1.00, green: 0.37, blue: 0.34),
                   symbol: "xmark", label: mini == nil ? "Cerrar ventana" : "Volver al reproductor")
            button(.minimize, color: Color(red: 1.00, green: 0.79, blue: 0.19),
                   symbol: "minus", label: "Minimizar ventana")
            button(.zoom, color: Color(red: 0.23, green: 0.82, blue: 0.36),
                   symbol: mini == nil ? "plus" : "arrow.up.left.and.arrow.down.right",
                   label: mini == nil ? "Ampliar / restaurar ventana" : "Alternar barra y tarjeta")
        }
        .padding(.trailing, mini == nil ? 6 : 0)
    }

    private func button(_ kind: Kind, color: Color, symbol: String, label: String) -> some View {
        Button {
            if let mini = mini {
                switch kind {
                case .close: mini.returnToMain()
                case .minimize: mini.minimizePanel()
                case .zoom: mini.expanded.toggle()
                }
            } else {
                guard let win = AppWindow.main else { return }
                switch kind {
                case .close: win.performClose(nil)
                case .minimize: win.miniaturize(nil)
                case .zoom: win.zoom(nil)
                }
            }
        } label: {
            Circle()
                .fill(color)
                .overlay {
                    if hovered == kind {
                        Image(systemName: symbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black.opacity(0.58))
                    }
                }
                .frame(width: 12, height: 12)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? kind : nil }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Ventana principal de la app, incluso cuando el mini reproductor está visible.
private enum AppWindow {
    static var main: NSWindow? {
        if let win = NSApp.keyWindow, !(win is NSPanel), win.title == "Música Local" { return win }
        if let win = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title == "Música Local" }) {
            return win
        }
        return NSApp.windows.first { !($0 is NSPanel) }
    }
}

