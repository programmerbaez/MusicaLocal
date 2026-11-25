import Foundation

/// Preferencias portables en el mismo directorio que library.json y Artworks.
struct MusicSettings: Codable {
    var version: Int = 1
    var theme: String = "system"
    var accentMode: String = "artwork"
    var customAccentHex: String? = nil
    var translucent: Bool = true
    var visualizer: String = "bars"
    var folderPath: String? = nil
    var cacheEnabled: Bool = true
    var audioEnabled: Bool = false
    var audioProfile: String = "balanced"
    var shortcuts: [String: Shortcut] = [:]

    static func current(folder: String?) -> MusicSettings {
        let ud = UserDefaults.standard
        let mode = ud.string(forKey: "accentMode") ?? "artwork"
        let map = (ud.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) }) ?? [:]
        return MusicSettings(version: 1,
            theme: ud.string(forKey: "theme") ?? "system",
            accentMode: mode,
            customAccentHex: mode == "custom" ? ud.string(forKey: "accentHex") : nil,
            translucent: ud.object(forKey: "translucentBackground") as? Bool ?? true,
            visualizer: ud.string(forKey: "visualizerStyle") ?? "bars",
            folderPath: folder,
            cacheEnabled: ud.object(forKey: "cacheEnabled") as? Bool ?? true,
            audioEnabled: ud.bool(forKey: "audioEnhancementEnabled"),
            audioProfile: ud.string(forKey: "audioProfile") ?? "balanced",
            shortcuts: map)
    }

    func apply() {
        let ud = UserDefaults.standard
        ud.set(theme, forKey: "theme")
        ud.set(accentMode, forKey: "accentMode")
        if accentMode == "custom", let hex = customAccentHex { ud.set(hex, forKey: "accentHex") }
        ud.set(translucent, forKey: "translucentBackground")
        ud.set(visualizer, forKey: "visualizerStyle")
        ud.set(cacheEnabled, forKey: "cacheEnabled")
        ud.set(audioEnabled, forKey: "audioEnhancementEnabled")
        ud.set(audioProfile, forKey: "audioProfile")
        if let data = try? JSONEncoder().encode(shortcuts) {
            ud.set(data, forKey: "shortcuts")
            ud.set(Array(shortcuts.keys), forKey: "shortcutsKnown")
        }
    }
}

final class SettingsStore {
    static let shared = SettingsStore()
    static var fileURL: URL { CacheStore.directory.appendingPathComponent("settings.json") }
    static func load() -> MusicSettings? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MusicSettings.self, from: data)
    }
    static func restoreAtLaunch() {
        guard UserDefaults.standard.bool(forKey: "setupCompleted"), let settings = load() else { return }
        settings.apply()
    }

    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    weak var player: Player?

    func start(player: Player) {
        self.player = player
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard,
            queue: .main) { [weak self] _ in self?.scheduleSave() }
    }
    func scheduleSave() {
        guard UserDefaults.standard.bool(forKey: "setupCompleted") else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func save() {
        guard UserDefaults.standard.bool(forKey: "setupCompleted") else { return }
        let folder = player?.folderURL?.path ?? Self.load()?.folderPath
        let settings = MusicSettings.current(folder: folder)
        do {
            try FileManager.default.createDirectory(at: CacheStore.directory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(settings).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Música Local: no se pudieron guardar los ajustes: %@", String(describing: error))
        }
    }
}
