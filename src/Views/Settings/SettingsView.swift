// Música Local — SettingsView
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Ajustes

struct CacheInfo {
    var folder: String?
    var tracks: Int
    var librarySize: String
    var artworkSize: String
    var exists: Bool

    static func current() -> CacheInfo {
        let c = CacheStore.load()
        let art = ArtworkDisk.sizeBytes
        let bytes = { (b: Int64) in ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        return CacheInfo(folder: c?.folderPath,
                         tracks: c?.entries.count ?? 0,
                         librarySize: bytes(CacheStore.sizeBytes),
                         artworkSize: bytes(art),
                         exists: c != nil || art > 0)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance, shortcuts, audio, visualizer, lyrics, cache
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appearance: return "Apariencia"
        case .shortcuts: return "Atajos"
        case .audio: return "Audio"
        case .visualizer: return "Visualizador"
        case .lyrics: return "Letras"
        case .cache: return "Caché"
        }
    }
    var icon: String {
        switch self {
        case .appearance: return "circle.lefthalf.filled"
        case .shortcuts: return "command"
        case .audio: return "waveform"
        case .visualizer: return "waveform.path"
        case .lyrics: return "music.note.list"
        case .cache: return "internaldrive"
        }
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var p: Player
    @EnvironmentObject var accent: AccentModel
    @EnvironmentObject private var lyricsSync: LyricsSync
    @ObservedObject private var shortcuts = ShortcutManager.shared

    @AppStorage("translucentBackground") private var translucentBackground = true
    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("cacheEnabled") private var cacheEnabled = true
    @AppStorage("visualizerStyle") private var visualizerStyleRaw = VisualizerStyle.bars.rawValue
    @AppStorage("lyricsFollow") private var lyricsFollow = true
    @AppStorage("lyricsAnimate") private var lyricsAnimate = true
    @AppStorage("lyricsWords") private var lyricsWords = true
    @AppStorage("lyricsSuspendOnScroll") private var lyricsSuspendOnScroll = true
    @AppStorage("lyricsScrollMetadata") private var lyricsScrollMetadata = false
    @AppStorage("lyricsActiveTextAccent") private var lyricsActiveTextAccent = true
    @AppStorage("lyricsOffsets") private var lyricsOffsets = Data()
    @State private var info = CacheInfo.current()

    @State private var selectedTab: SettingsTab = .appearance

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button { selectedTab = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 23, weight: .regular))
                                .frame(height: 29)
                            Text(tab.label).font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .foregroundColor(selectedTab == tab ? accent.shown.color : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        // El acento identifica solo el icono y el nombre de la pestaña.
                        // No aplicar fondo tintado ni material traslúcido a la selección.
                    }
                    .buttonStyle(.plain)
                    .help(tab.label)
                }
            }
            .padding(.horizontal, 25)
            .padding(.top, 9)
            .padding(.bottom, 7)
            Divider()
            Group {
                switch selectedTab {
                case .appearance: appearanceTab
                case .shortcuts: shortcutsTab
                case .audio: audioTab
                case .visualizer: visualizerTab
                case .lyrics: lyricsTab
                case .cache: cacheTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 500)
        .foregroundColor(scheme == .light ? AppearancePalette.charcoal : .primary)
        .appAccent(accent)
        .background(AppearanceSurface())
        .onAppear { info = CacheInfo.current() }
        .onDisappear { shortcuts.endRecording() }
        .onChange(of: themeRaw) { new in
            (AppTheme(rawValue: new) ?? .system).apply(animated: true)
        }
    }

    // MARK: Apariencia

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tema").font(.headline)
            HStack(spacing: 18) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeCard(theme: theme, selected: themeRaw == theme.rawValue) {
                        themeRaw = theme.rawValue
                    }
                }
            }
            Text("“Sistema” sigue la apariencia clara u oscura de macOS.")
                .font(.caption).foregroundColor(.secondary)

            Divider().padding(.vertical, 2)

            Toggle("Habilitar fondo translúcido", isOn: $translucentBackground)
                .toggleStyle(.checkbox)
            Text("Activado: material de vidrio. Desactivado: fondo sólido marfil en modo claro o gris carbón en modo oscuro. Se aplica también a los mini reproductores.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)

            Group {
                Text("Color de acento").font(.headline)
                Picker("", selection: $accent.mode) {
                    ForEach(AccentMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                accentDetail
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var accentDetail: some View {
        switch accent.mode {
        case .system:
            Text("Usa el color de acento definido en Ajustes del Sistema.")
                .font(.caption).foregroundColor(.secondary)
        case .artwork:
            HStack(spacing: 10) {
                Circle()
                    .fill(accent.shown.color)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                Text("Se adapta con una transición suave a la carátula de la canción en reproducción, tanto en tema claro como oscuro. Si no tiene carátula, usa el color del sistema.")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .custom:
            HStack(spacing: 12) {
                ColorPicker("Color único", selection: customBinding, supportsOpacity: false)
                Text(accent.customHex.uppercased())
                    .font(.caption).monospacedDigit().foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private var customBinding: Binding<Color> {
        Binding(
            get: { Color(NSColor(hex: accent.customHex) ?? NSColor.controlAccentColor) },
            set: { accent.customHex = NSColor($0).hexString }
        )
    }

    // MARK: Visualizador (solo representación gráfica; no modifica el sonido)

    private var visualizerTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Visualización de audio").font(.headline)
            Text("Selecciona el diseño del visualizador para el reproductor principal y ambos mini reproductores.")
                .font(.caption).foregroundColor(.secondary)

            Picker("Estilo", selection: $visualizerStyleRaw) {
                ForEach(VisualizerStyle.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text((VisualizerStyle(rawValue: visualizerStyleRaw) ?? .bars).description)
                .font(.caption).foregroundColor(.secondary)

            Divider()
            Text("Vista previa").font(.subheadline)
            Group {
                if visualizerStyleRaw == VisualizerStyle.off.rawValue {
                    Text("Visualizador desactivado")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 55)
                } else {
                    AudioLevelVisualizer(clock: p.clock, tint: accent.shown.color)
                        .frame(height: 55)
                        .padding(.horizontal, 16)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.055))
            .cornerRadius(10)

            Text("Las figuras reaccionan al nivel de la señal, no a bandas de frecuencia calculadas por FFT. No afectan el audio y conservan el color de acento de la carátula.")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Audio experimental

    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Procesamiento de audio (experimental)")
                .font(.headline)
            Text("Usa AVAudioEngine y un ecualizador nativo de cinco bandas. Se conserva el reproductor original como alternativa. No reconstruye información perdida ni cambia el archivo de música.")
                .font(.caption).foregroundColor(.secondary)

            Toggle("Activar mejoras de sonido", isOn: $p.audioEnhancementEnabled)
                .toggleStyle(.switch)

            Picker("Perfil de sonido", selection: $p.audioProfile) {
                ForEach(AudioProfile.allCases) { profile in
                    Text(profile.label).tag(profile)
                }
            }
            .disabled(!p.audioEnhancementEnabled)

            Text("Para comparar, elige Original o desactiva las mejoras. El perfil de graves/voces incluye una reserva de ganancia para reducir la posibilidad de saturación, pero no es un limitador profesional.")
                .font(.caption).foregroundColor(.secondary)

            if let warning = p.audioEngineWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Text("Recomendación: comienza con Equilibrado, compara durante varios minutos con Original y observa CPU y memoria en Monitor de Actividad. Si hay cortes o un comportamiento inesperado, desactiva el interruptor para volver al motor original.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Atajos

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atajos de teclado").font(.headline)
            Text("Haz clic en un atajo y pulsa la combinación que quieras usar. Esc cancela. Funcionan con la ventana principal activa y no se disparan mientras escribes en el buscador.")
                .font(.caption).foregroundColor(.secondary)

            Divider()

            ForEach(ShortcutAction.allCases) { action in
                HStack(spacing: 10) {
                    Label(action.label, systemImage: action.icon)
                        .frame(width: 180, alignment: .leading)
                    ShortcutField(mgr: shortcuts, action: action)
                    Button { shortcuts.reset(action) } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Restablecer")
                    Button { shortcuts.clear(action) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Quitar atajo")
                    Spacer()
                }
            }

            Divider()

            Text("Fijos: ↑ ↓ mueven la selección de la lista · ↩ reproduce la canción seleccionada · ⌘L muestra la canción actual.")
                .font(.caption).foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button { shortcuts.resetAll() } label: {
                    Label("Restablecer todos", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .padding(24)
    }

    // MARK: Caché

    private var cacheTab: some View {
        // Evita la superficie opaca del NSScrollView de Monterey, que
        // oscurecía la cabecera de esta pestaña respecto de las demás.
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $cacheEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guardar caché de la biblioteca").font(.headline)
                    Text("Recuerda la carpeta elegida, los metadatos y las miniaturas de carátulas para abrir la biblioteca al instante.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: cacheEnabled) { on in
                if on { p.saveCache() } else { p.clearCache() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    info = CacheInfo.current()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Carpeta de música").font(.headline)
                Text(p.folderURL?.path ?? "No hay ninguna carpeta seleccionada")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button {
                    p.chooseFolder()
                    // La selección se publica en Player; refrescar el resumen al volver del panel.
                    info = CacheInfo.current()
                } label: {
                    Label(p.folderURL == nil ? "Seleccionar carpeta…" : "Cambiar carpeta…",
                          systemImage: "folder.badge.plus")
                }
                Text("Al cambiar de carpeta se carga la nueva biblioteca. La caché es opcional.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                infoRow("Carpeta recordada", info.folder ?? "Ninguna", "folder.fill")
                infoRow("Canciones en caché", "\(info.tracks)", "music.note.list")
                infoRow("Metadatos (library.json)", info.librarySize, "doc.text")
                infoRow("Miniaturas de carátulas", info.artworkSize, "photo.on.rectangle")
            }

            Divider()
            lyricsSyncSection

            Spacer()

            HStack {
                Button {
                    p.reload()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { info = CacheInfo.current() }
                } label: {
                    Label("Actualizar biblioteca", systemImage: "arrow.clockwise")
                }
                .disabled(p.folderURL == nil)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([CacheStore.directory])
                } label: {
                    Label("Mostrar en Finder", systemImage: "folder")
                }
                .disabled(!info.exists)

                Spacer()

                Button(role: .destructive) {
                    p.clearCache()
                    ArtworkStore.shared.reset(clearDisk: false)
                    info = CacheInfo.current()
                } label: {
                    Label("Borrar caché", systemImage: "trash")
                }
                .disabled(!info.exists)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var lyricsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Seguir automáticamente la línea actual", isOn: $lyricsFollow)
            Toggle("Animar el desplazamiento", isOn: $lyricsAnimate)
            Toggle("Resaltar palabras con marcas de tiempo", isOn: $lyricsWords)
            Toggle("Usar el color de acento en el texto activo", isOn: $lyricsActiveTextAccent)
            Picker("Título y artista largos", selection: $lyricsScrollMetadata) {
                Text("Puntos suspensivos (…)").tag(false)
                Text("Desplazamiento automático").tag(true)
            }
            .pickerStyle(.menu)
            Toggle("Suspender el seguimiento al desplazar manualmente", isOn: $lyricsSuspendOnScroll)
            if let track = p.nowPlaying {
                Button("Restablecer el desfase de la canción actual") {
                    lyricsOffsets = LyricsOffsets.updating(lyricsOffsets, trackID: track.id, steps: 0)
                }
                .disabled(LyricsOffsets.steps(in: lyricsOffsets, trackID: track.id) == 0)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lyricsSyncSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Letras sin conexión").font(.headline)
                Spacer()
                if lyricsSync.isRunning {
                    Button("Cancelar") { lyricsSync.cancel() }
                } else {
                    Button {
                        lyricsSync.start(p.tracks)
                    } label: {
                        Label("Sincronizar letras", systemImage: "arrow.down.circle")
                    }
                    .disabled(p.tracks.isEmpty || p.isScanning)
                }
            }
            if let progress = lyricsSync.progress {
                if lyricsSync.isRunning {
                    ProgressView(value: Double(progress.checked), total: Double(progress.total))
                }
                Text("\(progress.checked) de \(progress.total) revisadas · \(progress.available) con letra · \(progress.pending) pendientes · \(progress.failed) fallidas")
                    .font(.caption).foregroundColor(.secondary)
                if let completion = lyricsSync.completion {
                    Text(completion).font(.caption).foregroundColor(.secondary)
                }
            } else {
                Text("Busca letras de tu biblioteca en LRCLIB para verlas sin internet.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Label(label, systemImage: icon)
                .foregroundColor(.secondary)
                .frame(width: 210, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

struct ShortcutField: View {
    @ObservedObject var mgr: ShortcutManager
    let action: ShortcutAction

    var body: some View {
        let recording = mgr.recording == action
        Button {
            if recording { mgr.endRecording() } else { mgr.beginRecording(action) }
        } label: {
            Text(recording ? "Pulsa las teclas…" : (mgr.map[action]?.display ?? "Sin asignar"))
                .frame(minWidth: 130)
        }
        .buttonStyle(.bordered)
        .tint(recording ? Color.orange : nil)
    }
}

struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: selected ? 2.5 : 1)
                    Image(systemName: theme.icon)
                        .font(.system(size: 26))
                        .foregroundColor(selected ? .accentColor : .primary)
                }
                .frame(width: 100, height: 66)

                Text(theme.label)
                    .font(.callout)
                    .foregroundColor(selected ? .accentColor : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

