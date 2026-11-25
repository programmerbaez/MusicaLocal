import SwiftUI
import AppKit

/// Ventana de ayuda integrada; funciona sin Internet y sin Apple Help Book.
enum HelpMusicaLocal {
    private static var window: NSWindow?

    static func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ayuda de Música Local"
        window.minSize = NSSize(width: 510, height: 410)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HelpMusicaLocalView())
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HelpMusicaLocalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ayuda de Música Local").font(.title2).bold()
                        Text("Guía rápida · Versión 1.0").font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Divider()
                // Agrupar las secciones evita superar los 10 elementos directos
                // del VStack en macOS 12 con Swift 5.7.
                Group {
                section("Empezar a escuchar", "Abre Configuración → Caché → Cambiar carpeta… para seleccionar tu biblioteca. Música Local carga las canciones y recuerda la ubicación elegida.")
                section("Reproducción y cola", "Pulsa dos veces una canción para reproducirla. El botón Cola muestra las canciones siguientes. Puedes añadir pistas manualmente, cambiar el modo aleatorio y elegir la repetición.")
                section("Mini reproductores", "Desde la ventana principal cambia al mini reproductor. Puedes alternar entre las vistas compacta y ampliada, usar los controles de volumen y regresar a la ventana principal.")
                section("Atajos", "Espacio: reproducir o pausar. ⌘← / ⌘→: anterior y siguiente. Los demás atajos pueden consultarse y personalizarse en Configuración → Atajos.")
                section("Audio y visualizador", "En Configuración → Audio puedes habilitar el procesamiento experimental y seleccionar un perfil. En Visualizador puedes elegir cinco estilos o desactivar las animaciones.")
                section("Apariencia y preferencias", "En Apariencia puedes elegir el tema, el acento de carátula o un color único y el fondo translúcido. La configuración se guarda en settings.json junto a la caché de la biblioteca.")
                }
                Divider()
                HStack(spacing: 18) {
                    Button("Licencia MIT") { LegalDocuments.open("LICENSE") }
                    Button("Términos de uso") { LegalDocuments.open("TERMINOS_Y_CONDICIONES") }
                    Button("Privacidad") { LegalDocuments.open("PRIVACIDAD") }
                }
                .buttonStyle(.link)
                Text("Música Local es gratuito y de código abierto. © 2026 Andrés Báez.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(27)
        }
        .background(AppearanceSurface())
    }

    private func section(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(description).font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
