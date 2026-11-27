import CryptoKit
import Foundation

actor LyricsStore {
    static let shared = LyricsStore()

    enum Result {
        case lyrics(Lyrics), instrumental, unavailable, missingMetadata
    }

    enum LookupError: LocalizedError {
        case rateLimited, service

        var errorDescription: String? {
            switch self {
            case .rateLimited: return "LRCLIB pidió una pausa. Vuelve a intentarlo más tarde."
            case .service: return "LRCLIB no pudo responder a la búsqueda de letras."
            }
        }
    }

    private struct Record: Codable {
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?

        var result: Result {
            if instrumental { return .instrumental }
            let lyrics = Lyrics(lrc: syncedLyrics ?? "", plainText: plainLyrics ?? "")
            return lyrics.isEmpty ? .unavailable : .lyrics(lyrics)
        }
    }

    private let directory = CacheStore.directory.appendingPathComponent("Lyrics", isDirectory: true)
    private var retryAfter = Date.distantPast
    private var requesting = false

    func lyrics(for track: Track, duration: Double, requireOfflineCopy: Bool = false) async throws -> Result {
        try Task.checkCancellation()
        let local = track.url.deletingPathExtension().appendingPathExtension("lrc")
        if let source = try? String(contentsOf: local) {
            let lyrics = Lyrics(lrc: source)
            if lyrics.hasTiming { return .lyrics(lyrics) }
        }

        let signature = [track.id, String(track.mtime), track.title, track.artist, track.album]
            .joined(separator: "\u{0}")
        let key = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = directory.appendingPathComponent(key).appendingPathExtension("js")
        if let record = readRecord(at: cached) {
            return record.result
        }
        if let record = readRecord(at: cached.deletingPathExtension().appendingPathExtension("json")) {
            try persist(record, at: cached, required: requireOfflineCopy)
            return record.result
        }

        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return .missingMetadata }
        // Las descargas de biblioteca dejan margen para las consultas interactivas.
        try await Task.sleep(nanoseconds: requireOfflineCopy ? 800_000_000 : 250_000_000)
        while requesting {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        try Task.checkCancellation()
        if let record = readRecord(at: cached) { return record.result }
        guard Date() >= retryAfter else { throw LookupError.rateLimited }
        requesting = true
        defer { requesting = false }

        var url = URLComponents()
        url.scheme = "https"
        url.host = "lrclib.net"
        url.path = "/api/get"
        var query = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { query.append(URLQueryItem(name: "album_name", value: album)) }
        let seconds = duration.rounded()
        if (1...3600).contains(seconds) { query.append(URLQueryItem(name: "duration", value: String(Int(seconds)))) }
        url.queryItems = query
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let endpoint = url.url else { throw LookupError.service }
        var request = URLRequest(url: endpoint, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let version = AppVersion.current ?? "desarrollo"
        request.setValue("MusicaLocal/\(version) (https://github.com/programmerbaez/MusicaLocal)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw LookupError.service }
        switch http.statusCode {
        case 200:
            guard data.count <= 1_048_576, let record = try? JSONDecoder().decode(Record.self, from: data)
            else { throw LookupError.service }
            let result = record.result
            if case .unavailable = result { return result }
            try persist(record, at: cached, required: requireOfflineCopy)
            return result
        case 404:
            return .unavailable
        case 429, 503:
            let header = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            let delay = max(1, header.flatMap { $0.isFinite ? $0 : nil } ?? 60)
            retryAfter = Date().addingTimeInterval(delay + Double.random(in: 0...(delay * 0.15)))
            throw LookupError.rateLimited
        default:
            throw LookupError.service
        }
    }

    private func readRecord(at url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func persist(_ record: Record, at url: URL, required: Bool) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
        } catch {
            if required { throw error }
        }
    }
}
