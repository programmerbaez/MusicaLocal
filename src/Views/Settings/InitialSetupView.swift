import SwiftUI
import AppKit

/// Asistente inicial, compatible con SwiftUI de macOS Monterey.
struct InitialSetupView: View {
    @ObservedObject var player: Player
    @ObservedObject var accent: AccentModel
    let finished: () -> Void

    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("translucentBackground") private var translucent = true
    @AppStorage("visualizerStyle") private var visualizerRaw = VisualizerStyle.bars.rawValue
    @AppStorage("cacheEnabled") private var cacheEnabled = true
    @State private var step = 0
    @State private var accepted = false
    @State private var importDecision = false
    @State private var imported = false
    @ObservedObject private var shortcuts = ShortcutManager.shared

    private let stages = ["Bienvenida", "Acuerdos", "Configuración existente", "Apariencia", "Atajos", "Audio", "Visualizador", "Biblioteca", "Finalizar"]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 22)).foregroundColor(accent.shown.color)
                Text("Música Local").font(.title2)
                Spacer()
                Text("\(step + 1) / \(stages.count)")
                    .foregroundColor(.secondary)
            }
            Divider()
            Text(stages[step]).font(.title2).bold()
            Group {
                switch step {
                case 0: welcome
                case 1: agreements
                case 2: importSettings
                case 3: appearance
                case 4: keyboard
                case 5: audio
                case 6: visualizer
                case 7: library
                default: completion
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Spacer(minLength: 4)
            Divider()
            HStack {
                if step > 0 { Button("Anterior") { step -= 1 } }
                Spacer()
                Button(step == stages.count - 1 ? "Iniciar Música Local" : "Continuar") {
                    if step == stages.count - 1 { finish() }
                    else { step += 1 }
                }
                .disabled((step == 1 && !accepted) || (step == 2 && !importDecision))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 650, height: 510)
        .appAccent(accent)
        .background(AppearanceSurface())
        .interactiveDismissDisabled(true)
        .onDisappear { shortcuts.endRecording() }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60)).foregroundColor(accent.shown.color)
            Text("¡Hola! Te damos la bienvenida a Música Local.")
                .font(.title3)
            Text("Tu biblioteca musical, sin cuentas ni conexión obligatoria. Configuraremos las opciones básicas antes de comenzar.")
                .foregroundColor(.secondary)
            Text("Puedes modificar todas estas preferencias después en Configuración.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var agreements: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proyecto gratuito y de código abierto").font(.headline)
            Text("Música Local es una aplicación gratuita desarrollada por Andrés Báez y publicada bajo licencia MIT. Puedes consultar las condiciones completas y la política de privacidad en los documentos incluidos.")
            Text("La aplicación reproduce música local. La biblioteca, las carátulas y las preferencias se guardan en tu equipo. Debes contar con los derechos necesarios para utilizar tus archivos musicales.")
                .foregroundColor(.secondary)
            Text("Se distribuye tal cual, sin garantías. Las mejoras de audio son opcionales y pueden desactivarse.")
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("Leer términos") { openLegal("TERMINOS_Y_CONDICIONES") }
                Button("Licencia MIT") { openLegal("LICENSE") }
                Button("Privacidad") { openLegal("PRIVACIDAD") }
            }
            Toggle("He leído y acepto los términos y condiciones para continuar", isOn: $accepted)
                .toggleStyle(.checkbox)
        }
    }

    private func openLegal(_ name: String) {
        if let url = Bundle.main.url(forResource: name, withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }

    private var importSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if SettingsStore.load() != nil {
                Text("Se encontró settings.json junto a la caché de la biblioteca. Puedes recuperar su apariencia, atajos, audio, visualizador y carpeta de música.")
                Button("Importar configuración existente") { importExisting() }
                Button("Crear configuración nueva desde cero") { resetNew() }
                if importDecision { Text(imported ? "Configuración importada." : "Se aplicarán los valores nuevos.").foregroundColor(.secondary) }
            } else {
                Text("No se encontró un settings.json previo. Puedes continuar con una configuración nueva.")
                    .foregroundColor(.secondary)
                Button("Crear configuración nueva") { resetNew() }
                if importDecision { Text("Configuración nueva seleccionada.").foregroundColor(.secondary) }
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Tema").font(.headline)
            Picker("Apariencia", selection: $themeRaw) {
                ForEach(AppTheme.allCases) { item in Text(item.label).tag(item.rawValue) }
            }
            .pickerStyle(.segmented)
            Toggle("Habilitar fondo translúcido", isOn: $translucent)
            Divider()
            Text("Color de acento").font(.headline)
            Picker("Color", selection: $accent.mode) {
                ForEach(AccentMode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            if accent.mode == .custom {
                ColorPicker("Color único", selection: Binding(
                    get: { Color(NSColor(hex: accent.customHex) ?? .controlAccentColor) },
                    set: { accent.customHex = NSColor($0).hexString }), supportsOpacity: false)
            }
        }
        .onChange(of: themeRaw) { raw in (AppTheme(rawValue: raw) ?? .system).apply(animated: true) }
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Selecciona cada combinación para cambiarla. También puedes restaurar los atajos predeterminados.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    Text(action.label).frame(width: 190, alignment: .leading)
                    ShortcutField(mgr: shortcuts, action: action)
                    Button("Restablecer") { shortcuts.reset(action) }
                }
            }
            Button("Restablecer todos") { shortcuts.resetAll() }
        }
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Activar mejoras de audio (experimental)", isOn: $player.audioEnhancementEnabled)
            Picker("Perfil", selection: $player.audioProfile) {
                ForEach(AudioProfile.allCases) { item in Text(item.label).tag(item) }
            }
            .disabled(!player.audioEnhancementEnabled)
            Text("Desactivado, Música Local utiliza el motor original. Si hay cortes o consumo excesivo, puedes desactivar el procesamiento en Configuración → Audio.")
                .foregroundColor(.secondary)
        }
    }

    private var visualizer: some View {
        VStack(alignment: .leading, spacing: 15) {
            Picker("Visualizador", selection: $visualizerRaw) {
                ForEach(VisualizerStyle.allCases) { item in Text(item.label).tag(item.rawValue) }
            }
            Text((VisualizerStyle(rawValue: visualizerRaw) ?? .bars).description)
                .foregroundColor(.secondary)
            if visualizerRaw != VisualizerStyle.off.rawValue {
                AudioLevelVisualizer(clock: player.clock, tint: accent.shown.color)
                    .frame(height: 85)
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Selecciona una carpeta con tu biblioteca musical. Puedes omitirlo y elegirla después en Configuración → Caché.")
            Text(player.folderURL?.path ?? "Ninguna carpeta seleccionada")
                .font(.caption).foregroundColor(.secondary).lineLimit(3)
            Button("Seleccionar carpeta de música…") { player.chooseFolder() }
            Toggle("Guardar caché de biblioteca", isOn: $cacheEnabled)
            Text("Los archivos library.json, settings.json y la carpeta Artworks se almacenan en el directorio de soporte de Música Local.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46)).foregroundColor(accent.shown.color)
            Text("Todo listo para escuchar música.").font(.title3)
            Text("Tu selección se guardará en settings.json. Podrás volver a modificarla cuando quieras desde Ajustes.")
            Text(player.folderURL?.path ?? "Puedes añadir una carpeta de música más adelante.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func importExisting() {
        guard let data = SettingsStore.load() else { return }
        data.apply()
        themeRaw = data.theme
        translucent = data.translucent
        visualizerRaw = data.visualizer
        accent.mode = AccentMode(rawValue: data.accentMode) ?? .artwork
        if let hex = data.customAccentHex { accent.customHex = hex }
        player.audioProfile = AudioProfile(rawValue: data.audioProfile) ?? .balanced
        player.audioEnhancementEnabled = data.audioEnabled
        cacheEnabled = data.cacheEnabled
        shortcuts.restore(data.shortcuts)
        if let folder = data.folderPath, FileManager.default.fileExists(atPath: folder) {
            player.loadFolder(URL(fileURLWithPath: folder, isDirectory: true))
        }
        imported = true
        importDecision = true
    }

    private func resetNew() {
        themeRaw = AppTheme.system.rawValue
        translucent = true
        visualizerRaw = VisualizerStyle.bars.rawValue
        accent.mode = .artwork
        cacheEnabled = true
        player.audioEnhancementEnabled = false
        player.audioProfile = .balanced
        shortcuts.resetAll()
        player.resetLibraryForSetup()
        imported = false
        importDecision = true
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "setupCompleted")
        SettingsStore.shared.save()
        finished()
    }
}
