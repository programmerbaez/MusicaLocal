// Música Local — MusicaLocal
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - App

@main
@MainActor
struct MusicaLocalApp: App {
    @StateObject private var player = Player()
    @StateObject private var accent = AccentModel()
    @StateObject private var mini = MiniPlayerController()
    @StateObject private var updates = UpdateChecker()
    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("setupCompleted") private var setupCompleted = false
    @State private var showingSetup = false

    init() { SettingsStore.restoreAtLaunch() }

    var body: some Scene {
        WindowGroup("Música Local") {
            ContentView(accent: accent)
                .environmentObject(player)
                .environmentObject(mini)
                .environmentObject(updates)
                .onAppear {
                    SpanishMenuLocalization.install()
                    mini.configure(player: player, accent: accent)
                    SettingsStore.shared.start(player: player)
                    if setupCompleted {
                        updates.checkAutomatically()
                    } else {
                        showingSetup = true
                    }
                    (AppTheme(rawValue: themeRaw) ?? .system).apply(animated: false)
                    let a = accent
                    player.onTrackChange = { [weak a] track in a?.trackChanged(track) }
                }
                .sheet(isPresented: $showingSetup, onDismiss: {
                    if setupCompleted { updates.checkAutomatically() }
                }) {
                    InitialSetupView(player: player, accent: accent) {
                        setupCompleted = true
                        showingSetup = false
                        SettingsStore.shared.save()
                    }
                }
                .onChange(of: themeRaw) { new in
                    (AppTheme(rawValue: new) ?? .system).apply(animated: true)
                }
                .alert(item: $updates.notice) { notice in
                    if let archive = notice.archive {
                        return Alert(
                            title: Text(notice.title), message: Text(notice.message),
                            primaryButton: .default(Text("Descargar e instalar")) { updates.install(archive) },
                            secondaryButton: .cancel(Text("Más tarde"))
                        )
                    }
                    return Alert(title: Text(notice.title), message: Text(notice.message),
                                 dismissButton: .default(Text("Aceptar")))
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de Música Local") { AboutMusicaLocal.show() }
                Button(updates.installing ? "Instalando actualización…" : "Buscar actualizaciones…") { updates.check() }
                    .disabled(updates.installing)
            }
            CommandGroup(replacing: .help) {
                Button("Ayuda de Música Local") { HelpMusicaLocal.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Configurar carpeta de música…") { openSettings() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Reproducción") {
                Button(player.isPlaying ? "Pausar" : "Reproducir") { player.togglePlay() }
                Button("Siguiente") { player.next() }
                Button("Anterior") { player.previous() }
                Divider()
                Toggle("Aleatorio", isOn: Binding(
                    get: { player.shuffle },
                    set: { player.shuffle = $0 }
                ))
                Menu("Repetir") {
                    ForEach(RepeatMode.allCases, id: \.self) { mode in
                        Toggle(mode.label, isOn: Binding(
                            get: { player.repeatMode == mode },
                            set: { _ in player.repeatMode = mode }
                        ))
                    }
                }
                Divider()
                Button("Mini reproductor / Ventana principal") { mini.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Divider()
                Group {
                    Button("Mostrar canción actual") { player.revealCurrent() }
                        .keyboardShortcut("l", modifiers: .command)
                    Button(player.volume > 0.01 ? "Silenciar" : "Activar sonido") { player.toggleMute() }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(player)
                .environmentObject(accent)
        }
    }
}
