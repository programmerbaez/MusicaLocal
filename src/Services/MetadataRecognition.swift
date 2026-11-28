import AVFoundation
import Foundation
import Darwin
import ImageIO

struct AcousticFingerprint {
    let value: String
    let duration: Int
}

protocol AcousticFingerprinting {
    func fingerprint(for url: URL) throws -> AcousticFingerprint
}

protocol MusicIdentifying {
    func identify(_ url: URL, userKey: String) async throws -> [MusicMatch]
    func editions(for recording: UUID) async throws -> [MusicEdition]
    func cover(for release: UUID) async throws -> MetadataCover?
}

struct MusicMatch: Identifiable {
    let id: UUID
    let title: String
    let artist: String
    let duration: Int?
    let score: Double
}

struct MusicEdition: Identifiable {
    let id: UUID
    let tags: [MusicTag: String]
    let detail: String
    // The same recording may appear more than once in one release.
    let releaseID: UUID
}

/// Uses the bundled library and AVFoundation's decoder. No executable or microphone is needed.
struct ChromaprintFingerprinting: AcousticFingerprinting {
    typealias Create = @convention(c) (Int32) -> OpaquePointer?
    typealias Free = @convention(c) (OpaquePointer) -> Void
    typealias Start = @convention(c) (OpaquePointer, Int32, Int32) -> Int32
    typealias Feed = @convention(c) (OpaquePointer, UnsafePointer<Int16>, Int32) -> Int32
    typealias Finish = @convention(c) (OpaquePointer) -> Int32
    typealias Get = @convention(c) (OpaquePointer, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
    typealias Deallocate = @convention(c) (UnsafeMutableRawPointer) -> Void

    var libraryURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("libchromaprint.dylib")

    func fingerprint(for url: URL) throws -> AcousticFingerprint {
        guard let library = libraryURL,
              let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
            throw MetadataError("Esta compilación no incluye una biblioteca Chromaprint compatible.")
        }
        defer { dlclose(handle) }
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else {
                throw MetadataError("La biblioteca Chromaprint incluida es incompatible.")
            }
            return unsafeBitCast(pointer, to: T.self)
        }
        let create = try symbol("chromaprint_new", Create.self)
        let free = try symbol("chromaprint_free", Free.self)
        let start = try symbol("chromaprint_start", Start.self)
        let feed = try symbol("chromaprint_feed", Feed.self)
        let finish = try symbol("chromaprint_finish", Finish.self)
        let get = try symbol("chromaprint_get_fingerprint", Get.self)
        let deallocate = try symbol("chromaprint_dealloc", Deallocate.self)
        let audio: AVAudioFile
        do { audio = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true) }
        catch { throw MetadataError("No se pudo decodificar el audio de este archivo para identificarlo.") }
        let format = audio.processingFormat
        guard format.channelCount > 0, format.channelCount <= 2, format.sampleRate >= 1000,
              format.sampleRate <= 384_000, audio.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192),
              let context = create(1) else {
            throw MetadataError("El formato o número de canales no es compatible con la identificación.")
        }
        defer { free(context) }
        let rate = Int32(format.sampleRate.rounded())
        let channels = Int32(format.channelCount)
        let duration = Double(audio.length) / format.sampleRate
        guard duration >= 2, duration <= Double(Int32.max), start(context, rate, channels) == 1 else {
            throw MetadataError("La duración o el formato no permiten generar una huella acústica.")
        }
        var frames = min(audio.length, Int64(rate) * 120)
        while frames > 0 {
            try Task.checkCancellation()
            try audio.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, frames)))
            guard buffer.frameLength > 0, let samples = buffer.int16ChannelData?[0],
                  feed(context, samples, Int32(buffer.frameLength) * channels) == 1 else {
                throw MetadataError("No se pudo procesar el audio para calcular la huella.")
            }
            frames -= Int64(buffer.frameLength)
        }
        var result: UnsafeMutablePointer<CChar>?
        guard finish(context) == 1, get(context, &result) == 1, let result = result else {
            throw MetadataError("No se pudo calcular una huella acústica.")
        }
        defer { deallocate(UnsafeMutableRawPointer(result)) }
        return AcousticFingerprint(value: String(cString: result), duration: Int(duration.rounded()))
    }
}

actor OnlineMusicIdentification: MusicIdentifying {
    static let shared = OnlineMusicIdentification()
    typealias Transport = (URLRequest, Int, Bool) async throws -> Data
    private let fingerprinting: AcousticFingerprinting
    private let clientKey: String?
    private let transport: Transport?
    private var nextRequest: [String: UInt64] = [:]
    private var identifying = false

    init(fingerprinting: AcousticFingerprinting = ChromaprintFingerprinting(),
         clientKey: String? = nil, transport: Transport? = nil) {
        self.fingerprinting = fingerprinting
        self.clientKey = clientKey
        self.transport = transport
    }

    func identify(_ url: URL, userKey: String) async throws -> [MusicMatch] {
        guard !identifying else { throw MetadataError("Ya hay una identificación en curso.") }
        guard let key = clientKey ?? ProcessInfo.processInfo.environment["MUSICALOCAL_ACOUSTID_CLIENT"]
                    ?? Bundle.main.object(forInfoDictionaryKey: "AcoustIDClientKey") as? String,
              !key.isEmpty else {
            throw MetadataError("Falta configurar la clave de aplicación de AcoustID.")
        }
        identifying = true
        defer { identifying = false }
        let fingerprint = try fingerprinting.fingerprint(for: url)
        var request = URLRequest(url: URL(string: "https://api.acoustid.org/v2/lookup")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var items = ["client": key, "duration": String(fingerprint.duration), "fingerprint": fingerprint.value,
                     "meta": "recordings", "format": "json"]
        if !userKey.isEmpty { items["user"] = userKey }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(items.sorted { $0.key < $1.key }.map { item in
            item.key + "=" + (item.value.addingPercentEncoding(withAllowedCharacters: safe) ?? "")
        }.joined(separator: "&").utf8)
        let data = try await fetch(request, limit: 2_000_000, interval: 400_000_000)
        let response = try JSONDecoder().decode(AcoustResponse.self, from: data)
        guard response.status == "ok" else {
            if response.error?.code == 21 { throw MetadataError("AcoustID requiere tu clave de usuario.") }
            throw MetadataError("AcoustID rechazó la consulta. Comprueba las claves de acceso.")
        }
        return Self.matches(from: response, duration: fingerprint.duration)
    }

    static func matches(from response: AcoustResponse, duration: Int) -> [MusicMatch] {
        var matches: [UUID: MusicMatch] = [:]
        for result in response.results ?? [] where (0...1).contains(result.score) {
            for recording in result.recordings ?? [] {
                guard let title = recording.title, !title.isEmpty,
                      let artist = recording.artists?.map(\.name).joined(separator: ", "), !artist.isEmpty else { continue }
                if let length = recording.duration, abs(Double(length) - Double(duration)) > max(8, Double(duration) * 0.05) {
                    continue
                }
                if (matches[recording.id]?.score ?? -1) >= result.score { continue }
                matches[recording.id] = MusicMatch(id: recording.id, title: title, artist: artist,
                                                   duration: recording.duration, score: result.score)
            }
        }
        return matches.values.sorted { $0.score == $1.score ? $0.id.uuidString < $1.id.uuidString : $0.score > $1.score }
    }

    func editions(for recording: UUID) async throws -> [MusicEdition] {
        var offset = 0
        var editions: [MusicEdition] = []
        while offset < 300 {
            var components = URLComponents(string: "https://musicbrainz.org/ws/2/release")!
            components.queryItems = [URLQueryItem(name: "recording", value: recording.uuidString.lowercased()),
                                     URLQueryItem(name: "inc", value: "recordings+artist-credits"),
                                     URLQueryItem(name: "fmt", value: "json"),
                                     URLQueryItem(name: "limit", value: "25"),
                                     URLQueryItem(name: "offset", value: String(offset))]
            let data = try await fetch(URLRequest(url: components.url!), limit: 12_000_000, interval: 1_100_000_000)
            let page = try JSONDecoder().decode(ReleasePage.self, from: data)
            for release in page.releases {
                for medium in release.media ?? [] {
                    for track in medium.tracks ?? [] where track.recording.id == recording {
                        var tags: [MusicTag: String] = [
                            .title: track.title ?? track.recording.title, .album: release.title,
                            .disc: String(medium.position), .track: track.number ?? String(track.position),
                            .recording: recording.uuidString.lowercased(),
                            .release: release.id.uuidString.lowercased()
                        ]
                        tags[.artist] = (track.credits ?? track.recording.credits).map(Self.artist)
                        tags[.albumArtist] = release.credits.map(Self.artist)
                        tags[.year] = release.date
                        let detail = [release.date, release.country, release.disambiguation, medium.format]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                        editions.append(MusicEdition(id: track.id, tags: tags, detail: detail, releaseID: release.id))
                    }
                }
            }
            offset += page.releases.count
            if page.releases.isEmpty || offset >= page.count { break }
        }
        if let data = try? await fetch(URLRequest(url: URL(string:
            "https://musicbrainz.org/ws/2/recording/\(recording.uuidString.lowercased())?inc=genres&fmt=json")!),
            limit: 512_000, interval: 1_100_000_000),
           let genres = (try? JSONDecoder().decode(RecordingGenres.self, from: data))?.genres,
           let genre = genres.max(by: { $0.count < $1.count })?.name {
            editions = editions.map {
                var tags = $0.tags
                tags[.genre] = genre
                return MusicEdition(id: $0.id, tags: tags, detail: $0.detail, releaseID: $0.releaseID)
            }
        }
        try Task.checkCancellation()
        var seen = Set<UUID>()
        return editions.filter { seen.insert($0.id).inserted }
    }

    private static func artist(_ credits: [Credit]) -> String {
        credits.map { $0.name + ($0.joinphrase ?? "") }.joined()
    }

    func cover(for release: UUID) async throws -> MetadataCover? {
        let url = URL(string: "https://coverartarchive.org/release/\(release.uuidString.lowercased())/front-500")!
        do {
            let data = try await fetch(URLRequest(url: url), limit: 5_000_000, cover: true)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source) as String?,
                  ["public.jpeg", "public.png"].contains(type),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...2000).contains(width), (1...2000).contains(height),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw MetadataError("La portada no es una imagen JPEG o PNG válida dentro del tamaño permitido.")
            }
            return MetadataCover(data: data, mime: type == "public.jpeg" ? "image/jpeg" : "image/png",
                                 width: width, height: height, depth: image.bitsPerPixel)
        } catch let error as HTTPFailure where error.status == 404 {
            return nil
        }
    }

    private func fetch(_ original: URLRequest, limit: Int, interval: UInt64 = 0, cover: Bool = false) async throws -> Data {
        if let transport = transport { return try await transport(original, limit, cover) }

        let host = original.url?.host ?? ""
        let now = DispatchTime.now().uptimeNanoseconds
        let start = max(now, nextRequest[host] ?? now)
        nextRequest[host] = start + interval
        if start > now { try await Task.sleep(nanoseconds: start - now) }
        try Task.checkCancellation()
        var request = original
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"
        request.setValue("MusicaLocal/\(version) (macOS metadata editor; https://github.com/programmerbaez/MusicaLocal)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 18
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: RedirectPolicy(cover: cover), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw MetadataError("Respuesta de red inválida.") }
        guard response.statusCode == 200 else {
            if response.statusCode == 429 || response.statusCode == 503 {
                let retry = response.value(forHTTPHeaderField: "Retry-After") ?? ""
                let date = DateFormatter()
                date.locale = Locale(identifier: "en_US_POSIX")
                date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                let seconds = Double(retry) ?? date.date(from: retry)?.timeIntervalSinceNow ?? 5
                let end = DispatchTime.now().uptimeNanoseconds + UInt64(min(86_400, max(1, seconds.isFinite ? seconds : 5)) * 1e9)
                nextRequest[host] = max(nextRequest[host] ?? 0, end)
            }
            throw HTTPFailure(status: response.statusCode)
        }
        let types = cover ? ["image/jpeg", "image/png"] : ["application/json"]
        guard types.contains(response.mimeType ?? ""), response.expectedContentLength <= Int64(limit) else {
            throw MetadataError("El tipo o tamaño de la respuesta excede lo permitido.")
        }
        var data = Data()
        for try await byte in stream {
            guard data.count < limit else { throw MetadataError("La descarga supera el tamaño permitido.") }
            data.append(byte)
        }
        return data
    }
}

struct HTTPFailure: LocalizedError {
    let status: Int
    var errorDescription: String? { "El servicio respondió con HTTP \(status). Inténtalo de nuevo más tarde." }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    let cover: Bool
    init(cover: Bool) { self.cover = cover }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard cover, let url = request.url, let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              host == "coverartarchive.org" || host == "archive.org" || host.hasSuffix(".archive.org"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            completionHandler(nil)
            return
        }
        components.scheme = "https"
        var redirected = request
        redirected.url = components.url
        completionHandler(redirected.url == nil ? nil : redirected)
    }
}

struct AcoustResponse: Decodable {
    struct Failure: Decodable { let code: Int }
    struct Match: Decodable {
        struct Recording: Decodable {
            struct Artist: Decodable { let name: String }
            let id: UUID
            let title: String?
            let duration: Int?
            let artists: [Artist]?
        }
        let score: Double
        let recordings: [Recording]?
    }
    let status: String
    let error: Failure?
    let results: [Match]?
}

private struct Credit: Decodable {
    let name: String
    let joinphrase: String?
}

private struct RecordingGenres: Decodable {
    struct Genre: Decodable { let name: String; let count: Int }
    let genres: [Genre]?
}

private struct ReleasePage: Decodable {
    struct Release: Decodable {
        struct Medium: Decodable {
            struct Track: Decodable {
                struct Recording: Decodable {
                    let id: UUID
                    let title: String
                    let credits: [Credit]?
                    enum CodingKeys: String, CodingKey { case id, title; case credits = "artist-credit" }
                }
                let id: UUID
                let title: String?
                let number: String?
                let position: Int
                let recording: Recording
                let credits: [Credit]?
                enum CodingKeys: String, CodingKey {
                    case id, title, number, position, recording
                    case credits = "artist-credit"
                }
            }
            let position: Int
            let format: String?
            let tracks: [Track]?
        }
        let id: UUID
        let title: String
        let date: String?
        let country: String?
        let disambiguation: String?
        let media: [Medium]?
        let credits: [Credit]?
        enum CodingKeys: String, CodingKey { case id, title, date, country, disambiguation, media; case credits = "artist-credit" }
    }
    let releases: [Release]
    let count: Int
    enum CodingKeys: String, CodingKey { case releases; case count = "release-count" }
}
