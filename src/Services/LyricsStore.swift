import CryptoKit
import Foundation

actor LyricsStore {
    static let shared = LyricsStore()

    enum Result {
        case lyrics(Lyrics), instrumental, unavailable, missingMetadata

        var hasLyrics: Bool {
            if case .lyrics = self { return true }
            return false
        }
    }

    enum LookupError: LocalizedError {
        case rateLimited, service, rejected

        var errorDescription: String? {
            switch self {
            case .rateLimited: return "LRCLIB pidió una pausa. Vuelve a intentarlo más tarde."
            case .service: return "LRCLIB no pudo responder a la búsqueda de letras."
            case .rejected: return "LRCLIB rechazó la consulta de letras."
            }
        }
    }

    private struct Record: Codable {
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let hasWordSync: Bool?
        let lyricsfile: String?

        var result: Result {
            if instrumental { return .instrumental }
            let timed = hasWordSync == true ? lyricsfile.map(LyricsfileTiming.parse) ?? [] : []
            let lyrics = Lyrics(lrc: syncedLyrics ?? "", plainText: plainLyrics ?? "", timedLines: timed)
            return lyrics.isEmpty ? .unavailable : .lyrics(lyrics)
        }
    }

    private struct Miss: Codable {
        let until: Date
        let duration: Double?
    }

    private let directory: URL
    private let session: URLSession
    private var retryAfter = Date.distantPast
    private var nextRequest = Date.distantPast
    private var requesting = false

    init(directory: URL = CacheStore.directory.appendingPathComponent("Lyrics", isDirectory: true),
         session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    func lyrics(for track: Track, duration: Double, requireOfflineCopy: Bool = false,
                refresh: Bool = false) async throws -> Result {
        try Task.checkCancellation()
        let local = track.url.deletingPathExtension().appendingPathExtension("lrc")
        if let source = try? String(contentsOf: local) {
            let lyrics = Lyrics(lrc: source)
            if !lyrics.isEmpty { return .lyrics(lyrics) }
        }

        let signature = [track.id, String(track.mtime), track.title, track.artist, track.album]
            .joined(separator: "\u{0}")
        let key = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = directory.appendingPathComponent(key).appendingPathExtension("js")
        let miss = cached.deletingPathExtension().appendingPathExtension("miss")
        let seconds = duration.isFinite && duration >= 1 ? duration : nil
        if let result = try cachedResult(at: cached, required: requireOfflineCopy) { return result }
        if !refresh && isRecentMiss(at: miss, duration: seconds) { return .unavailable }

        let title = Self.cleaned(track.title)
        let artist = Self.cleaned(track.artist)
        let album = Self.cleaned(track.album)
        guard !title.isEmpty, !artist.isEmpty else { return .missingMetadata }

        try await Task.sleep(nanoseconds: requireOfflineCopy ? 500_000_000 : 150_000_000)
        while requesting || Date() < retryAfter {
            try Task.checkCancellation()
            if !requesting && !requireOfflineCopy { throw LookupError.rateLimited }
            try await Task.sleep(nanoseconds: Date() < retryAfter ? 1_000_000_000 : 150_000_000)
        }
        try Task.checkCancellation()
        // La búsqueda anterior pudo completar esta pista mientras esperábamos.
        if let result = try cachedResult(at: cached, required: requireOfflineCopy) { return result }
        if !refresh && isRecentMiss(at: miss, duration: seconds) { return .unavailable }
        requesting = true
        defer { requesting = false }

        var query = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { query.append(URLQueryItem(name: "album_name", value: album)) }
        if let rounded = seconds?.rounded(), rounded <= 3600 {
            query.append(URLQueryItem(name: "duration", value: String(Int(rounded))))
        }
        if let data = try await request("/api/get", query: query) {
            guard let record = try? JSONDecoder().decode(Record.self, from: data) else { throw LookupError.service }
            if Self.matches(record, title: title, artist: artist, duration: seconds, allowVariant: false),
               let result = try saveIfAvailable(record, at: cached, required: requireOfflineCopy) {
                return result
            }
        }

        let base = Self.baseTitle(title)
        let fallback = [URLQueryItem(name: "track_name", value: base), URLQueryItem(name: "artist_name", value: artist)]
        if let data = try await request("/api/search", query: fallback) {
            guard let records = try? JSONDecoder().decode([Record].self, from: data) else { throw LookupError.service }
            let matches = records.filter {
                Self.matches($0, title: title, artist: artist, duration: seconds, allowVariant: true)
            }.sorted {
                Self.rank($0, title: title, album: album, duration: seconds)
                    < Self.rank($1, title: title, album: album, duration: seconds)
            }
            for record in matches {
                if let result = try saveIfAvailable(record, at: cached, required: requireOfflineCopy) { return result }
            }
        }
        try persist(Miss(until: Date().addingTimeInterval(6 * 3600), duration: seconds), at: miss, required: false)
        return .unavailable
    }

    private static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalized(_ text: String) -> String {
        cleaned(text).folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func baseTitle(_ text: String) -> String {
        let base = text.replacingOccurrences(
            of: #"(?i)\s*(?:[\(\[][^\)\]]*(?:remix|remaster|version|edit|live|deluxe|acoustic|en vivo)[^\)\]]*[\)\]]|[–—-]\s+.*(?:remix|remaster|version|edit|live|acoustic|en vivo).*)\s*$"#,
            with: "", options: .regularExpression)
        return base.isEmpty ? text : cleaned(base)
    }

    private static func matches(_ record: Record, title: String, artist: String, duration: Double?, allowVariant: Bool) -> Bool {
        guard let remoteTitle = record.trackName, let remoteArtist = record.artistName,
              normalized(remoteArtist) == normalized(artist) else { return false }
        if let duration = duration {
            guard let remoteDuration = record.duration, remoteDuration.isFinite,
                  abs(remoteDuration - duration) <= 3 else { return false }
        }
        if normalized(remoteTitle) == normalized(title) { return true }
        // Una variante solo es aceptable si también coincide la duración.
        return allowVariant && duration != nil && normalized(baseTitle(remoteTitle)) == normalized(baseTitle(title))
    }

    private static func rank(_ record: Record, title: String, album: String, duration: Double?) -> Double {
        let titlePenalty = normalized(record.trackName ?? "") == normalized(title) ? 0.0 : 8.0
        let albumPenalty = album.isEmpty || normalized(record.albumName ?? "") == normalized(album) ? 0.0 : 4.0
        let difference = duration.map { abs((record.duration ?? $0) - $0) } ?? 0
        return titlePenalty + albumPenalty + difference
    }

    private func request(_ path: String, query: [URLQueryItem]) async throws -> Data? {
        let delay = nextRequest.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()

        var url = URLComponents()
        url.scheme = "https"
        url.host = "lrclib.net"
        url.path = path
        url.queryItems = query
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let endpoint = url.url else { throw LookupError.rejected }
        var request = URLRequest(url: endpoint, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let version = AppVersion.current ?? "desarrollo"
        request.setValue("MusicaLocal/\(version) (https://github.com/programmerbaez/MusicaLocal)", forHTTPHeaderField: "User-Agent")
        defer { nextRequest = Date().addingTimeInterval(0.5) }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw LookupError.service }
        switch http.statusCode {
        case 200:
            guard data.count <= 4_194_304 else { throw LookupError.service }
            return data
        case 404: return nil
        case 429, 503:
            let fallback: TimeInterval = http.statusCode == 429 ? 60 : 2
            retryAfter = Self.retryDate(http.value(forHTTPHeaderField: "Retry-After"), now: Date(), fallback: fallback)
            throw LookupError.rateLimited
        case 400..<500: throw LookupError.rejected
        default: throw LookupError.service
        }
    }

    static func retryDate(_ header: String?, now: Date, fallback: TimeInterval) -> Date {
        if let value = header?.trimmingCharacters(in: .whitespaces) {
            if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
            if let date = formatter.date(from: value) { return max(now, date) }
        }
        return now.addingTimeInterval(fallback)
    }

    private func isRecentMiss(at url: URL, duration: Double?) -> Bool {
        guard let miss: Miss = read(at: url), miss.until > Date() else { return false }
        if let cachedDuration = miss.duration, let duration = duration {
            return abs(cachedDuration - duration) <= 0.5
        }
        return miss.duration == nil && duration == nil
    }

    private func cachedResult(at url: URL, required: Bool) throws -> Result? {
        if let record: Record = read(at: url) {
            let result = record.result
            switch result {
            case .lyrics, .instrumental: return result
            case .unavailable, .missingMetadata: break
            }
        }
        if let legacy: Record = read(at: url.deletingPathExtension().appendingPathExtension("json")) {
            return try saveIfAvailable(legacy, at: url, required: required)
        }
        return nil
    }

    private func saveIfAvailable(_ record: Record, at url: URL, required: Bool) throws -> Result? {
        let result = record.result
        if case .unavailable = result { return nil }
        try persist(record, at: url, required: required)
        return result
    }

    private func read<T: Decodable>(at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), data.count <= 4_194_304 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persist<T: Encodable>(_ record: T, at url: URL, required: Bool) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
        } catch {
            if required { throw error }
        }
    }
}
