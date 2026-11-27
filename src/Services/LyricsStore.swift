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

    func lyrics(for track: Track, duration: Double) async throws -> Result {
        let local = track.url.deletingPathExtension().appendingPathExtension("lrc")
        if let source = try? String(contentsOf: local) {
            let lyrics = Lyrics(lrc: source)
            if lyrics.hasTiming { return .lyrics(lyrics) }
        }

        let signature = [track.id, String(track.mtime), track.title, track.artist, track.album]
            .joined(separator: "\u{0}")
        let key = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = directory.appendingPathComponent(key).appendingPathExtension("json")
        if let data = try? Data(contentsOf: cached),
           let record = try? JSONDecoder().decode(Record.self, from: data) {
            return record.result
        }

        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return .missingMetadata }
        // Evita iniciar una consulta nueva por cada pulsación rápida de «Siguiente».
        try await Task.sleep(nanoseconds: 250_000_000)
        guard Date() >= retryAfter else { throw LookupError.rateLimited }

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
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(record) { try? encoded.write(to: cached, options: .atomic) }
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
}
