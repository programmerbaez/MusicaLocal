// Música Local — AccentViews
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

/// Aplica el acento animado a toda la jerarquía de vistas. Solo este modificador (y el fondo)
/// observan al modelo, así que la lista no se reconstruye en cada fotograma de la animación.
struct AccentApplier: ViewModifier {
    @ObservedObject var model: AccentModel
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let c = model.shown.color
        return content
            .accentColor(c)
            .tint(c)
            .onAppear { model.setScheme(dark: scheme == .dark) }
            .onChange(of: scheme) { new in model.setScheme(dark: new == .dark) }
    }
}

extension View {
    func appAccent(_ model: AccentModel) -> some View {
        modifier(AccentApplier(model: model))
    }
}

/// Superficie compartida por la ventana principal y ambos mini reproductores.
/// El modo translúcido puede desactivarse sin alterar los controles ni el motor de audio.
enum AppearancePalette {
    static let bone = Color(red: 0.961, green: 0.949, blue: 0.925)  // #F5F2EC
    static let charcoal = Color(red: 0.19, green: 0.20, blue: 0.21) // #303336
    static let darkSurface = Color(red: 0.115, green: 0.12, blue: 0.13)
}

struct AppearanceSurface: View {
    @AppStorage("translucentBackground") private var translucent = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if translucent {
                MainVisualEffect()
                    // Calienta el material en modo claro sin convertirlo en blanco puro.
                    .overlay(scheme == .light ? AppearancePalette.bone.opacity(0.48) : Color.clear)
            } else {
                (scheme == .light ? AppearancePalette.bone : AppearancePalette.darkSurface)
            }
        }
        .ignoresSafeArea()
    }
}

/// Material nativo conservado para macOS Monterey (sin degradado de carátula).
struct MainVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct AccentBackground: View {
    var body: some View { AppearanceSurface() }
}
