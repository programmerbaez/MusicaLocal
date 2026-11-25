// Música Local — ShortcutManager
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Atajos de teclado configurables

enum ShortcutAction: String, CaseIterable, Identifiable {
    case playPause, previous, next, shuffle, repeatMode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .playPause:  return "Reproducir / Pausar"
        case .previous:   return "Anterior"
        case .next:       return "Siguiente"
        case .shuffle:    return "Aleatorio"
        case .repeatMode: return "Repetir"
        }
    }

    var icon: String {
        switch self {
        case .playPause:  return "playpause.fill"
        case .previous:   return "backward.fill"
        case .next:       return "forward.fill"
        case .shuffle:    return "shuffle"
        case .repeatMode: return "repeat"
        }
    }
}

struct Shortcut: Codable, Equatable {
    var key: String
    var mods: UInt

    init(key: String, mods: UInt) {
        self.key = key
        self.mods = mods
    }

    init?(event: NSEvent) {
        guard let c = event.charactersIgnoringModifiers?.lowercased(), let first = c.first else { return nil }
        key = String(first)
        mods = event.modifierFlags.intersection(ShortcutManager.relevant).rawValue
    }

    var display: String {
        let f = NSEvent.ModifierFlags(rawValue: mods)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + keyName
    }

    private var keyName: String {
        switch key {
        case " ":        return "Espacio"
        case "\u{F700}": return "↑"
        case "\u{F701}": return "↓"
        case "\u{F702}": return "←"
        case "\u{F703}": return "→"
        case "\r", "\u{3}": return "↩"
        case "\t":       return "⇥"
        case "\u{7F}":   return "⌫"
        case "\u{1B}":   return "⎋"
        default:
            if let u = key.unicodeScalars.first, (0xF704...0xF70F).contains(u.value) {
                return "F\(u.value - 0xF704 + 1)"
            }
            return key.uppercased()
        }
    }
}

final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static let defaults: [ShortcutAction: Shortcut] = [
        .playPause:  Shortcut(key: " ", mods: 0),
        .previous:   Shortcut(key: "\u{F702}", mods: NSEvent.ModifierFlags.command.rawValue),
        .next:       Shortcut(key: "\u{F703}", mods: NSEvent.ModifierFlags.command.rawValue),
        .shuffle:    Shortcut(key: "s", mods: NSEvent.ModifierFlags.command.rawValue),
        .repeatMode: Shortcut(key: "r", mods: NSEvent.ModifierFlags.command.rawValue)
    ]

    @Published private(set) var map: [ShortcutAction: Shortcut]
    @Published private(set) var recording: ShortcutAction?

    private weak var player: Player?
    private var monitor: Any?
    private var recorder: Any?

    private init() {
        let ud = UserDefaults.standard
        let stored = ud.data(forKey: "shortcuts")
        var m: [ShortcutAction: Shortcut] = [:]
        let known: Set<String>

        if let data = stored, let raw = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (k, v) in raw {
                if let a = ShortcutAction(rawValue: k) { m[a] = v }
            }
            // Versiones anteriores solo conocían estas cuatro acciones
            let legacy: Set<String> = ["playPause", "previous", "next", "shuffle"]
            known = ud.stringArray(forKey: "shortcutsKnown").map { Set($0) } ?? legacy
        } else {
            m = ShortcutManager.defaults
            known = Set(ShortcutAction.allCases.map { $0.rawValue })
        }

        // Acciones nuevas: asignarles su atajo por defecto si no choca con otro
        for a in ShortcutAction.allCases where !known.contains(a.rawValue) {
            if let d = ShortcutManager.defaults[a], !m.values.contains(d) { m[a] = d }
        }
        map = m
        ud.set(ShortcutAction.allCases.map { $0.rawValue }, forKey: "shortcutsKnown")
        save()
    }

    func restore(_ saved: [String: Shortcut]) {
        endRecording()
        var updated: [ShortcutAction: Shortcut] = [:]
        for (name, shortcut) in saved {
            if let action = ShortcutAction(rawValue: name) { updated[action] = shortcut }
        }
        map = updated
        save()
    }

    private func save() {
        var raw: [String: Shortcut] = [:]
        for (a, s) in map { raw[a.rawValue] = s }
        if let d = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(d, forKey: "shortcuts")
        }
    }

    /// Escucha de teclado dentro de la app: atajos configurables + navegación de la lista.
    /// Nunca actúa mientras el foco está en un campo de texto (p. ej. el buscador).
    func start(player: Player) {
        self.player = player
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.recording == nil else { return event }
            // La app tiene una ventana principal y un NSPanel con dos presentaciones.
            // El filtro anterior sólo admitía "Música Local" y desactivaba los
            // atajos cuando el foco estaba en el mini reproductor.
            guard let window = event.window else { return event }
            let isMainWindow = !(window is NSPanel) && window.title == "Música Local"
            let isMiniPlayer = window is NSPanel && window.title == "Mini reproductor"
            guard isMainWindow || isMiniPlayer else { return event }
            // No interceptar texto ni atajos mientras el usuario edita un campo.
            if window.firstResponder is NSText { return event }

            if let sc = Shortcut(event: event),
               let action = self.map.first(where: { $0.value == sc })?.key {
                if !event.isARepeat {
                    DispatchQueue.main.async { self.perform(action) }
                }
                return nil
            }

            // Navegación fija de la lista: ↑ ↓ y Return
            let mods = event.modifierFlags.intersection(ShortcutManager.relevant)
            if isMainWindow && mods.isEmpty, let p = self.player {
                switch event.keyCode {
                case 126:
                    DispatchQueue.main.async { p.moveSelection(-1) }
                    return nil
                case 125:
                    DispatchQueue.main.async { p.moveSelection(1) }
                    return nil
                case 36, 76:
                    if !event.isARepeat { DispatchQueue.main.async { p.playSelected() } }
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    private func perform(_ action: ShortcutAction) {
        guard let p = player else { return }
        switch action {
        case .playPause:  p.togglePlay()
        case .previous:   p.previous()
        case .next:       p.next()
        case .shuffle:    p.shuffle.toggle()
        case .repeatMode: p.repeatMode = p.repeatMode.cycled
        }
    }

    // Grabación de un nuevo atajo
    func beginRecording(_ action: ShortcutAction) {
        endRecording()
        recording = action
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let action = self.recording else { return event }
            if event.keyCode == 53 {            // Esc cancela
                self.endRecording()
                return nil
            }
            if let sc = Shortcut(event: event) {
                self.assign(sc, to: action)
            }
            self.endRecording()
            return nil
        }
    }

    func endRecording() {
        if let r = recorder { NSEvent.removeMonitor(r) }
        recorder = nil
        recording = nil
    }

    private func assign(_ sc: Shortcut, to action: ShortcutAction) {
        for (a, s) in map where s == sc && a != action { map[a] = nil }
        map[action] = sc
        save()
    }

    func clear(_ action: ShortcutAction) {
        map[action] = nil
        save()
    }

    func reset(_ action: ShortcutAction) {
        if let d = ShortcutManager.defaults[action] { assign(d, to: action) } else { clear(action) }
    }

    func resetAll() {
        map = ShortcutManager.defaults
        save()
    }
}

