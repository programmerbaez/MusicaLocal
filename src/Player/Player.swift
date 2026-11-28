// Música Local — Player
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Reproductor

final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var tracks: [Track] = [] { didSet { rebuildVisible() } }
    @Published private(set) var visible: [Track] = []
    @Published var query = "" { didSet { rebuildVisible() } }
    @Published var sortKey: SortKey? = nil { didSet { rebuildVisible() } }
    @Published var ascending = true { didSet { rebuildVisible() } }

    @Published private(set) var playlists = PlaylistStore.load()
    @Published private(set) var activePlaylistID: Playlist.ID?
    @Published private(set) var unavailablePlaylistPaths: [String] = []

    var activePlaylist: Playlist? { playlists.first { $0.id == activePlaylistID } }

    @Published var selectedID: String?
    @Published private(set) var scrollRequest: ScrollRequest?

    @Published private(set) var nowPlaying: Track? {
        didSet {
            if oldValue?.id != nowPlaying?.id { onTrackChange?(nowPlaying) }
            bridge?.scheduleRefresh()
        }
    }
    @Published private(set) var isPlaying = false {
        didSet { bridge?.scheduleRefresh() }
    }
    @Published private(set) var folderURL: URL?
    @Published private(set) var folderName = ""
    @Published private(set) var missingFolder: String?
    @Published private(set) var isScanning = false
    @Published private(set) var metaDone = 0
    @Published private(set) var metaTotal = 0

    @Published var volume: Double = 0.8 {
        didSet {
            player?.volume = Float(volume)
            enhanced?.setVolume(volume)
            UserDefaults.standard.set(volume, forKey: "volume")
            if volume > 0.01 {
                lastNonZeroVolume = volume
                UserDefaults.standard.set(volume, forKey: "lastVolume")
            }
        }
    }

    @Published var shuffle = false {
        didSet {
            UserDefaults.standard.set(shuffle, forKey: "shuffle")
            shufflePlayed = nowPlaying.map { [$0.id] } ?? []
            rebuildShufflePlan()
        }
    }

    @Published var repeatMode: RepeatMode = .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") }
    }

    @Published var audioEnhancementEnabled = false {
        didSet {
            UserDefaults.standard.set(audioEnhancementEnabled, forKey: "audioEnhancementEnabled")
            if oldValue != audioEnhancementEnabled { switchAudioBackend() }
        }
    }
    @Published var audioProfile: AudioProfile = .balanced {
        didSet {
            UserDefaults.standard.set(audioProfile.rawValue, forKey: "audioProfile")
            enhanced?.setProfile(audioProfile)
        }
    }

    let clock = PlaybackClock()
    var isSeeking = false
    var onTrackChange: ((Track?) -> Void)?

    var currentPosition: Double { enhanced?.currentTime ?? player?.currentTime ?? 0 }

    private var player: AVAudioPlayer?
    private var enhanced: AudioEnhancementEngine?
    @Published private(set) var audioEngineWarning: String?
    private var timer: Timer?
    private var cache: LibraryCache?
    private var failures = 0
    @Published private(set) var upcomingQueue: [Track] = []
    private var history: [String] = []
    private var shufflePlayed = Set<String>()
    /// Orden aleatorio ya decidido: la cola visual y el botón Siguiente consumen la misma secuencia.
    @Published private(set) var shufflePlan: [Track] = []
    private var shufflePlanIDs = Set<String>()
    private var lastNonZeroVolume = 0.8
    private var scrollNonce = 0
    private var bridge: NowPlayingBridge?

    private var generation = 0
    private let genLock = NSLock()
    private let libraryScanQueue = DispatchQueue(label: "com.local.musicalocal.library-scan", qos: .background)

    static let exts: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf"]

    private var cacheEnabled: Bool {
        UserDefaults.standard.bool(forKey: "cacheEnabled")
    }

    override init() {
        super.init()
        let ud = UserDefaults.standard
        ud.register(defaults: [
            "cacheEnabled": true,
            "theme": AppTheme.system.rawValue,
            "volume": 0.8,
            "lastVolume": 0.8,
            "shuffle": false,
            "repeatMode": RepeatMode.off.rawValue
        ])
        lastNonZeroVolume = max(ud.double(forKey: "lastVolume"), 0.1)
        volume = ud.double(forKey: "volume")
        shuffle = ud.bool(forKey: "shuffle")
        repeatMode = RepeatMode(rawValue: ud.string(forKey: "repeatMode") ?? "") ?? .off
        // Por seguridad, el motor experimental está desactivado por defecto.
        audioProfile = AudioProfile(rawValue: ud.string(forKey: "audioProfile") ?? "") ?? .balanced
        audioEnhancementEnabled = ud.bool(forKey: "audioEnhancementEnabled")
        bridge = NowPlayingBridge(player: self)
        ShortcutManager.shared.start(player: self)
        if ud.bool(forKey: "setupCompleted") { restoreLastFolder() }
    }

    // MARK: Generación (cancelación de escaneos antiguos)

    private func bumpGeneration() -> Int {
        genLock.lock(); defer { genLock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ g: Int) -> Bool {
        genLock.lock(); defer { genLock.unlock() }
        return generation == g
    }

    // MARK: Carpeta

    private func restoreLastFolder() {
        if let saved = SettingsStore.load()?.folderPath {
            var exists: ObjCBool = false
            if FileManager.default.fileExists(atPath: saved, isDirectory: &exists), exists.boolValue {
                loadFolder(URL(fileURLWithPath: saved, isDirectory: true))
                return
            }
        }
        guard cacheEnabled, let c = CacheStore.load() else { return }
        cache = c
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: c.folderPath, isDirectory: &isDir), isDir.boolValue {
            loadFolder(URL(fileURLWithPath: c.folderPath, isDirectory: true))
        } else {
            missingFolder = c.folderPath
        }
    }

    /// Reinicia únicamente la selección de biblioteca durante el asistente inicial.
    func resetLibraryForSetup() {
        stopPlayback()
        _ = bumpGeneration()
        folderURL = nil
        folderName = ""
        missingFolder = nil
        cache = nil
        tracks = []
        history = []
        upcomingQueue = []
        shufflePlan = []
        shufflePlanIDs = []
        shufflePlayed = []
        selectedID = nil
        isScanning = false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        panel.message = "Selecciona la carpeta con tu música"
        panel.directoryURL = folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFolder(url)
    }

    func reload() {
        guard let u = folderURL else { return }
        ArtworkStore.shared.reset(clearDisk: true)
        loadFolder(u, useCache: false)
    }

    func loadFolder(_ url: URL, useCache: Bool = true) {
        stopPlayback()
        let g = bumpGeneration()
        folderURL = url
        SettingsStore.shared.scheduleSave()
        folderName = url.lastPathComponent
        missingFolder = nil
        history = []
        upcomingQueue = []
        shufflePlan = []
        shufflePlanIDs = []
        shufflePlayed = []
        selectedID = nil
        ArtworkStore.shared.reset(clearDisk: false)
        tracks = []
        isScanning = true
        metaDone = 0
        metaTotal = 0

        let usable = useCache && cacheEnabled
            && cache?.folderPath == url.path
            && cache?.version == LibraryCache.currentVersion
        let cached: [String: CachedTrack] = usable ? (cache?.entries ?? [:]) : [:]

        libraryScanQueue.async { [weak self] in
            guard let self = self, self.isCurrent(g) else { return }

            var initial: [Track] = []
            var pending: [Track] = []
            let keys: [URLResourceKey] = [.contentModificationDateKey]

            if let en = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let file as URL in en {
                    guard self.isCurrent(g) else { return }
                    guard Player.exts.contains(file.pathExtension.lowercased()) else { continue }
                    let mtime = (try? file.resourceValues(forKeys: Set(keys)))?
                        .contentModificationDate?.timeIntervalSince1970 ?? 0
                    if let c = cached[file.path], c.mtime == mtime {
                        initial.append(Track(url: file, title: c.title, artist: c.artist,
                                             album: c.album, duration: c.duration,
                                             mtime: mtime, loaded: true))
                    } else {
                        let parsed = FilenameParser.parse(file.deletingPathExtension().lastPathComponent)
                        let t = Track(url: file,
                                      title: parsed.title,
                                      artist: parsed.artist ?? "",
                                      album: "", duration: 0,
                                      mtime: mtime, loaded: false)
                        initial.append(t)
                        pending.append(t)
                    }
                }
            }

            initial.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            let pendingCount = pending.count

            DispatchQueue.main.sync {
                guard self.isCurrent(g) else { return }
                self.tracks = initial
                self.metaTotal = pendingCount
                self.saveCache()
                if pendingCount == 0 { self.isScanning = false }
            }
            if pendingCount == 0 { return }

            // Los lotes cortos permiten reajustar la prioridad al reproducir o pausar.
            let chunkSize = 8
            let workerCount = 2
            var start = 0
            var buffered: [Track] = []
            var nextUpdate = DispatchTime.now() + .milliseconds(250)
            while start < pending.count {
                guard self.isCurrent(g) else { return }
                let qos: DispatchQoS.QoSClass = DispatchQueue.main.sync {
                    self.isPlaying ? .background : .utility
                }
                let end = min(start + chunkSize, pending.count)
                let chunk = Array(pending[start..<end])
                let workers = min(workerCount, chunk.count)
                let group = DispatchGroup()
                let results = MetadataBatch()
                for worker in 0..<workers {
                    DispatchQueue.global(qos: qos).async(group: group) {
                        var updated: [Track] = []
                        for index in stride(from: worker, to: chunk.count, by: workers) {
                            guard self.isCurrent(g) else { return }
                            updated.append(autoreleasepool { Player.readTrack(chunk[index]) })
                        }
                        results.append(updated)
                    }
                }
                group.wait()
                guard self.isCurrent(g) else { return }
                buffered.append(contentsOf: results.tracks)
                start = end

                let finished = end == pendingCount
                guard finished || DispatchTime.now() >= nextUpdate else {
                    continue
                }
                // Esperar la publicación evita acumular actualizaciones si la ventana está ocupada.
                DispatchQueue.main.sync {
                    guard self.isCurrent(g) else { return }
                    self.apply(buffered)
                    self.metaDone = end
                    if finished {
                        self.isScanning = false
                        self.saveCache()
                    }
                }
                buffered.removeAll(keepingCapacity: true)
                nextUpdate = DispatchTime.now() + .milliseconds(250)
            }
        }
    }

    private final class MetadataBatch {
        private let lock = NSLock()
        private var results: [Track] = []

        var tracks: [Track] {
            lock.lock()
            defer { lock.unlock() }
            return results
        }

        func append(_ tracks: [Track]) {
            lock.lock()
            defer { lock.unlock() }
            results.append(contentsOf: tracks)
        }
    }

    // MARK: Metadatos

    static func readTrack(_ t: Track) -> Track {
        var r = t
        let asset = AVURLAsset(url: t.url)
        let md = asset.commonMetadata

        func str(_ key: AVMetadataKey) -> String {
            let items = AVMetadataItem.metadataItems(from: md, withKey: key, keySpace: .common)
            return (items.first?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var title = str(.commonKeyTitle)
        var artist = str(.commonKeyArtist)
        let parsed = FilenameParser.parse(t.url.deletingPathExtension().lastPathComponent)

        if title.isEmpty {
            title = parsed.title
            if artist.isEmpty, let a = parsed.artist { artist = a }
        } else if artist.isEmpty, let a = parsed.artist,
                  parsed.title.caseInsensitiveCompare(title) == .orderedSame {
            artist = a                                   // archivo "Artista - Título" con etiqueta de título
        }

        r.title = title
        r.artist = artist
        r.album = str(.commonKeyAlbumName)
        let d = asset.duration.seconds
        r.duration = d.isFinite ? d : 0
        r.loaded = true
        return r
    }

    private func apply(_ updated: [Track]) {
        var copy = tracks
        var index: [String: Int] = [:]
        for (i, t) in copy.enumerated() { index[t.id] = i }
        for u in updated {
            if let i = index[u.id] { copy[i] = u }
        }
        tracks = copy
        if let id = nowPlaying?.id, let u = updated.first(where: { $0.id == id }) {
            nowPlaying = u
        }
    }

    // MARK: Listas de reproducción

    func createPlaylist(named name: String) throws {
        let playlist = try PlaylistStore.create(named: name)
        playlists.append(playlist)
        playlists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selectPlaylist(playlist.id)
    }

    func selectPlaylist(_ id: Playlist.ID?) {
        guard activePlaylistID != id else { return }
        activePlaylistID = id
        selectedID = nil
        shufflePlayed = nowPlaying.map { [$0.id] } ?? []
        rebuildVisible(resetShuffle: true)
    }

    func addToPlaylist(_ track: Track, playlistID: Playlist.ID) throws {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].trackPaths.contains(track.id) else { return }
        var playlist = playlists[index]
        playlist.trackPaths.append(track.id)
        try updatePlaylist(playlist, at: index)
    }

    func removeFromActivePlaylist(path: String) throws {
        guard let index = playlists.firstIndex(where: { $0.id == activePlaylistID }) else { return }
        var playlist = playlists[index]
        playlist.trackPaths.removeAll { $0 == path }
        try updatePlaylist(playlist, at: index)
        if selectedID == path { selectedID = nil }
    }

    private func updatePlaylist(_ playlist: Playlist, at index: Int) throws {
        try PlaylistStore.save(playlist)
        playlists[index] = playlist
        if playlist.id == activePlaylistID { rebuildVisible() }
    }

    // MARK: Lista visible (filtro + orden)

    private func rebuildVisible(resetShuffle: Bool = false) {
        var list = tracks
        var unavailable: [String] = []
        if let playlist = activePlaylist {
            let paths = Set(playlist.trackPaths)
            let matching = tracks.filter { paths.contains($0.id) }
            let byID = Dictionary(matching.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            list = playlist.trackPaths.compactMap { byID[$0] }
            unavailable = playlist.trackPaths.filter { byID[$0] == nil }
        }
        if unavailablePlaylistPaths != unavailable { unavailablePlaylistPaths = unavailable }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                || $0.artist.localizedCaseInsensitiveContains(q)
                || $0.album.localizedCaseInsensitiveContains(q)
            }
        }
        if let key = sortKey {
            let asc = ascending
            list.sort { a, b in
                let r: ComparisonResult
                switch key {
                case .title:  r = a.title.localizedCaseInsensitiveCompare(b.title)
                case .artist: r = a.artist.localizedCaseInsensitiveCompare(b.artist)
                case .album:  r = a.album.localizedCaseInsensitiveCompare(b.album)
                case .duration:
                    r = a.duration < b.duration ? .orderedAscending
                      : (a.duration > b.duration ? .orderedDescending : .orderedSame)
                }
                if r == .orderedSame {
                    return a.url.path.localizedStandardCompare(b.url.path) == .orderedAscending
                }
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
        }
        visible = list
        let ids = Set(list.map { $0.id })
        if resetShuffle || ids != shufflePlanIDs {
            rebuildShufflePlan()
        } else if shuffle && !shufflePlan.isEmpty {
            // Al cargar metadatos, conservar el orden previsto y actualizar su información.
            let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            shufflePlan = shufflePlan.compactMap { byID[$0.id] }
        }
    }

    func toggleSort(_ key: SortKey) {
        if sortKey == key {
            if ascending { ascending = false } else { sortKey = nil; ascending = true }
        } else {
            sortKey = key
            ascending = true
        }
    }

    // MARK: Selección y desplazamiento

    private func requestScroll(id: String, center: Bool, revealLibrary: Bool = false) {
        scrollNonce += 1
        scrollRequest = ScrollRequest(id: id, center: center, nonce: scrollNonce, revealLibrary: revealLibrary)
    }

    /// Lleva la lista hasta la canción que está sonando.
    func revealCurrent(revealLibrary: Bool = true) {
        guard let id = nowPlaying?.id, visible.contains(where: { $0.id == id }) else { return }
        requestScroll(id: id, center: true, revealLibrary: revealLibrary)
    }

    func moveSelection(_ delta: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        let idx: Int
        if let sel = selectedID, let i = list.firstIndex(where: { $0.id == sel }) {
            idx = min(max(i + delta, 0), list.count - 1)
        } else if let cur = nowPlaying, let i = list.firstIndex(where: { $0.id == cur.id }) {
            idx = i
        } else {
            idx = 0
        }
        let id = list[idx].id
        selectedID = id
        requestScroll(id: id, center: false)
    }

    func playSelected() {
        guard let sel = selectedID, let t = visible.first(where: { $0.id == sel }) else { return }
        play(t)
    }

    func selectFirstIfNeeded() {
        if selectedID == nil || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }

    // MARK: Caché

    func saveCache() {
        guard cacheEnabled, let folder = folderURL else { return }
        var entries: [String: CachedTrack] = [:]
        for t in tracks where t.loaded {
            entries[t.url.path] = CachedTrack(title: t.title, artist: t.artist,
                                              album: t.album, duration: t.duration, mtime: t.mtime)
        }
        let c = LibraryCache(folderPath: folder.path, entries: entries,
                             version: LibraryCache.currentVersion)
        cache = c
        DispatchQueue.global(qos: .utility).async { CacheStore.save(c) }
    }

    func clearCache() {
        cache = nil
        CacheStore.clear()
        ArtworkDisk.clear()
    }

    // MARK: Cola de reproducción manual (compartida entre todas las ventanas)

    /// Inserta una pista en la posición inmediatamente siguiente.
    func playNext(_ track: Track) {
        upcomingQueue.insert(track, at: 0)
    }

    /// Agrega una pista al final de la cola manual.
    func addToQueue(_ track: Track) {
        upcomingQueue.append(track)
    }

    func removeFromQueue(at index: Int) {
        guard upcomingQueue.indices.contains(index) else { return }
        upcomingQueue.remove(at: index)
    }

    func moveQueueItem(from source: Int, to destination: Int) {
        guard upcomingQueue.indices.contains(source),
              upcomingQueue.indices.contains(destination), source != destination else { return }
        let item = upcomingQueue.remove(at: source)
        upcomingQueue.insert(item, at: destination)
    }

    func clearQueue() { upcomingQueue.removeAll() }

    /// Reproduce el elemento de la cola manual seleccionado y conserva los posteriores.
    func playQueued(at index: Int) {
        guard upcomingQueue.indices.contains(index) else { return }
        let t = upcomingQueue.remove(at: index)
        play(t)
    }

    /// Salta a una canción de la cola automática sin insertar una copia manual.
    /// En aleatorio, descarta las canciones anteriores al elemento elegido,
    /// conservando el orden de las que quedan a continuación.
    func playAutomaticQueued(at index: Int) {
        let sequence = automaticUpcomingQueue
        guard sequence.indices.contains(index) else { return }
        let selected = sequence[index]
        if shuffle && repeatMode != .one {
            shufflePlan.removeFirst(min(index + 1, shufflePlan.count))
        }
        play(selected)
        revealCurrent(revealLibrary: false)
    }

    /// Plan estable generado una vez, no en cada render de SwiftUI.
    private func rebuildShufflePlan() {
        shufflePlanIDs = Set(visible.map { $0.id })
        guard shuffle else {
            shufflePlan = []
            return
        }
        shufflePlan = visible.filter {
            $0.id != nowPlaying?.id && !shufflePlayed.contains($0.id)
        }.shuffled()
    }

    /// Secuencia automática visible. El historial manual tiene prioridad, pero nunca
    /// modifica la secuencia futura hasta que realmente empieza a sonar una canción.
    var automaticUpcomingQueue: [Track] {
        let list = visible
        guard !list.isEmpty else { return [] }
        if repeatMode == .one, let current = nowPlaying { return [current] }
        if shuffle {
            // Cuando no quedan pistas, no se inventa un sorteo distinto al reproducir.
            return shufflePlan
        }
        let index = nowPlaying.flatMap { current in
            list.firstIndex(where: { $0.id == current.id })
        } ?? -1
        let tail = Array(list.dropFirst(index + 1))
        if repeatMode == .all && index >= 0 {
            return tail + Array(list.prefix(index + 1))
        }
        return tail
    }

    var automaticNextTrack: Track? { automaticUpcomingQueue.first }

    // MARK: Reproducción

    // Cambia de motor conservando canción, posición y estado de pausa.
    private func switchAudioBackend() {
        guard let track = nowPlaying else { return }
        let position = currentPosition
        let wasPlaying = isPlaying
        if audioEnhancementEnabled {
            do {
                let candidate = AudioEnhancementEngine()
                try candidate.load(url: track.url, profile: audioProfile, volume: volume)
                candidate.seek(position)
                if !wasPlaying { candidate.pause() }
                player?.stop()
                player = nil
                enhanced?.stop()
                enhanced = candidate
                audioEngineWarning = nil
            } catch {
                // El original sigue intacto si falla un formato o dispositivo.
                audioEngineWarning = "Motor experimental no disponible para esta pista: \(error.localizedDescription). Se usa audio original."
                audioEnhancementEnabled = false
            }
        } else {
            do {
                let original = try AVAudioPlayer(contentsOf: track.url)
                original.delegate = self
                original.volume = Float(volume)
                original.isMeteringEnabled = true
                original.prepareToPlay()
                original.currentTime = position
                if wasPlaying { original.play() }
                enhanced?.stop()
                enhanced = nil
                player = original
            } catch {
                audioEngineWarning = "No se pudo restaurar la salida original: \(error.localizedDescription)"
            }
        }
        clock.progress = position
        clock.audioLevel = 0
        isPlaying = wasPlaying
        startTimer()
    }

    func play(_ track: Track, recordHistory: Bool = true) {
        do {
            // Siempre conservar AVAudioPlayer como ruta fiable para archivos no compatibles.
            var original: AVAudioPlayer? = nil
            var processing: AudioEnhancementEngine? = nil
            if audioEnhancementEnabled {
                do {
                    let candidate = AudioEnhancementEngine()
                    try candidate.load(url: track.url, profile: audioProfile, volume: volume)
                    processing = candidate
                    audioEngineWarning = nil
                } catch {
                    audioEngineWarning = "Procesamiento omitido para \(track.title): \(error.localizedDescription)"
                }
            }
            if processing == nil {
                let p = try AVAudioPlayer(contentsOf: track.url)
                p.delegate = self
                p.volume = Float(volume)
                p.isMeteringEnabled = true
                p.prepareToPlay()
                p.play()
                original = p
            }
            player?.stop()
            enhanced?.stop()
            player = original
            enhanced = processing
            if recordHistory, let cur = nowPlaying, cur.id != track.id {
                history.append(cur.id)
                if history.count > 300 { history.removeFirst() }
            }
            shufflePlayed.insert(track.id)
            if shuffle {
                shufflePlan.removeAll { $0.id == track.id }
                if shufflePlan.isEmpty && repeatMode == .all {
                    // Comienza un nuevo ciclo de aleatorio sin repetir de inmediato la pista actual.
                    shufflePlayed = [track.id]
                    rebuildShufflePlan()
                }
            }
            clock.duration = processing?.duration ?? original?.duration ?? 0
            clock.progress = 0
            clock.audioLevel = 0
            failures = 0
            isPlaying = true
            nowPlaying = track
            startTimer()
        } catch {
            failures += 1
            nowPlaying = track
            if failures < max(visible.count, 1) {
                next()
            } else {
                failures = 0
                stopPlayback()
            }
        }
    }

    func togglePlay() {
        guard player != nil || enhanced != nil else {
            if shuffle { next() } else if let first = visible.first { play(first) }
            return
        }
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard isPlaying else { return }
        enhanced?.pause()
        player?.pause()
        isPlaying = false
        clock.audioLevel = 0
    }

    func resume() {
        guard player != nil || enhanced != nil else { togglePlay(); return }
        if !isPlaying {
            enhanced?.resume()
            player?.play()
            isPlaying = true
            startTimer()
        }
    }

    /// Avanza a la siguiente canción. `auto` indica que la pista terminó sola:
    /// en ese caso se respeta el modo Repetir (canción / lista / desactivado).
    func next(auto: Bool = false) {
        let list = visible

        // Una cola explícita tiene prioridad sobre la biblioteca y los modos de repetición.
        if !upcomingQueue.isEmpty {
            let queued = upcomingQueue.removeFirst()
            play(queued)
            if !auto { revealCurrent(revealLibrary: false) }
            return
        }

        guard !list.isEmpty else {
            if auto && activePlaylistID != nil { finishQueue() }
            return
        }

        if auto && repeatMode == .one, let cur = nowPlaying {
            play(cur, recordHistory: false)
            return
        }

        if shuffle {
            if shufflePlan.isEmpty {
                if auto && repeatMode == .off { finishQueue(); return }
                shufflePlayed = nowPlaying.map { [$0.id] } ?? []
                rebuildShufflePlan()
            }
            guard !shufflePlan.isEmpty else {
                if auto { finishQueue() }
                return
            }
            let pick = shufflePlan.removeFirst()
            play(pick)
            if !auto { revealCurrent(revealLibrary: false) }
            return
        }

        let idx = nowPlaying.flatMap { cur in list.firstIndex { $0.id == cur.id } } ?? -1
        if auto && repeatMode == .off && idx >= 0 && idx + 1 >= list.count {
            finishQueue()
            return
        }
        play(list[(idx + 1) % list.count])
        if !auto { revealCurrent(revealLibrary: false) }
    }

    func previous() {
        let list = visible
        guard !list.isEmpty else { return }

        if currentPosition > 3 {
            enhanced?.seek(0)
            player?.currentTime = 0
            clock.progress = 0
            bridge?.scheduleRefresh()
            return
        }

        if shuffle {
            let candidates = activePlaylistID == nil ? tracks : list
            while let id = history.popLast() {
                if let t = candidates.first(where: { $0.id == id }) {
                    let forward = nowPlaying
                    play(t, recordHistory: false)
                    if let forward = forward, forward.id != t.id,
                       activePlaylistID == nil || list.contains(forward) {
                        shufflePlan.removeAll { $0.id == forward.id }
                        shufflePlan.insert(forward, at: 0)
                    }
                    revealCurrent(revealLibrary: false)
                    return
                }
            }
            enhanced?.seek(0)
            player?.currentTime = 0
            clock.progress = 0
            return
        }

        let idx = nowPlaying.flatMap { cur in list.firstIndex { $0.id == cur.id } } ?? 0
        play(list[(idx - 1 + list.count) % list.count])
        revealCurrent(revealLibrary: false)
    }

    func seek(_ time: Double) {
        enhanced?.seek(time)
        player?.currentTime = time
        clock.progress = time
        bridge?.scheduleRefresh()
    }

    func toggleMute() {
        if volume > 0.01 { volume = 0 } else { volume = max(lastNonZeroVolume, 0.1) }
    }

    /// Fin de la cola (Repetir desactivado): se detiene y deja la última canción lista para volver a sonar.
    private func finishQueue() {
        enhanced?.stop()
        enhanced = nil
        player?.stop()
        player?.currentTime = 0
        timer?.invalidate()
        timer = nil
        clock.progress = 0
        clock.audioLevel = 0
        isPlaying = false
    }

    private func stopPlayback() {
        enhanced?.stop()
        enhanced = nil
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        nowPlaying = nil
        clock.progress = 0
        clock.duration = 0
        clock.audioLevel = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, !self.isSeeking else { return }
            self.clock.progress = self.currentPosition
            if let enhanced = self.enhanced {
                self.clock.audioLevel = self.isPlaying ? enhanced.level : 0
                if self.isPlaying && enhanced.reachedEnd { self.next(auto: true) }
            } else if let p = self.player, p.isPlaying {
                p.updateMeters()
                let power = (0..<max(1, p.numberOfChannels))
                    .map { Double(p.averagePower(forChannel: $0)) }
                    .max() ?? -80
                self.clock.audioLevel = min(1, max(0, (power + 50) / 50))
            } else {
                self.clock.audioLevel = 0
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard finished === self.player else { return }
            self.next(auto: true)
        }
    }
}

