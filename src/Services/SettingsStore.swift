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
    var lyricsFollow: Bool?
    var lyricsAnimate: Bool?
    var lyricsWords: Bool?
    var lyricsSuspendOnScroll: Bool?
    var lyricsScrollMetadata: Bool?
    var lyricsActiveTextAccent: Bool?
    var lyricsOffsets: [String: Int]?

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
            shortcuts: map,
            lyricsFollow: ud.object(forKey: "lyricsFollow") as? Bool ?? true,
            lyricsAnimate: ud.object(forKey: "lyricsAnimate") as? Bool ?? true,
            lyricsWords: ud.object(forKey: "lyricsWords") as? Bool ?? true,
            lyricsSuspendOnScroll: ud.object(forKey: "lyricsSuspendOnScroll") as? Bool ?? true,
            lyricsScrollMetadata: ud.bool(forKey: "lyricsScrollMetadata"),
            lyricsActiveTextAccent: ud.object(forKey: "lyricsActiveTextAccent") as? Bool ?? true,
            lyricsOffsets: ud.data(forKey: "lyricsOffsets").map(LyricsOffsets.decode) ?? [:])
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
        if let lyricsFollow = lyricsFollow { ud.set(lyricsFollow, forKey: "lyricsFollow") }
        if let lyricsAnimate = lyricsAnimate { ud.set(lyricsAnimate, forKey: "lyricsAnimate") }
        if let lyricsWords = lyricsWords { ud.set(lyricsWords, forKey: "lyricsWords") }
        if let lyricsSuspendOnScroll = lyricsSuspendOnScroll { ud.set(lyricsSuspendOnScroll, forKey: "lyricsSuspendOnScroll") }
        if let lyricsScrollMetadata = lyricsScrollMetadata { ud.set(lyricsScrollMetadata, forKey: "lyricsScrollMetadata") }
        if let lyricsActiveTextAccent = lyricsActiveTextAccent { ud.set(lyricsActiveTextAccent, forKey: "lyricsActiveTextAccent") }
        if let lyricsOffsets = lyricsOffsets, let data = try? JSONEncoder().encode(lyricsOffsets) {
            ud.set(data, forKey: "lyricsOffsets")
        }
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

enum LyricsOffsets {
    static func decode(_ data: Data) -> [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    static func steps(in data: Data, trackID: String) -> Int {
        min(240, max(-240, decode(data)[trackID] ?? 0))
    }

    static func updating(_ data: Data, trackID: String, steps: Int) -> Data {
        var offsets = decode(data)
        offsets[trackID] = steps == 0 ? nil : steps
        return (try? JSONEncoder().encode(offsets)) ?? data
    }
}
