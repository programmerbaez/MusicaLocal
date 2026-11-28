import CryptoKit
import Foundation

private final class MockLyricsHTTP: URLProtocol {
    struct Reply {
        let status: Int
        var headers: [String: String] = [:]
        var body = ""
        var error: URLError?
    }

    static var response: (URLRequest) -> Reply = { _ in Reply(status: 404) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.response(request)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
private struct LyricsChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
        guard condition() else { fatalError(description) }
    }

    @MainActor
    static func main() async throws {
        checkTiming()
        try checkSettings()
        try await checkStore()
        print("OK: tiempos, ajustes anteriores, caché, coincidencias, HTTP 429/503 y reanudación")
    }

    private static func checkTiming() {
        let traditional = Lyrics(lrc: "[offset:250]\n[00:01]Uno\n[00:03]Doble\n[00:03]Última\n[00:04]♪")
        expect(traditional.lines.map(\.time) == [0, 0.75, 2.75, 2.75, 3.75], "LRC y offset")
        expect(traditional.lineIndex(at: 2.75) == 3, "Marcas duplicadas")
        expect(traditional.lines.last?.isInstrumental == true, "Tramo instrumental")
        expect(traditional.lines.allSatisfy { $0.words.isEmpty }, "LRC tradicional sin marcas de palabra")
        expect(traditional.lineIndex(at: 1 - 0.25) == 1, "Atrasar 0,25 s")
        expect(traditional.lineIndex(at: 0.5 + 0.25) == 1, "Adelantar 0,25 s")
        expect(traditional.lineIndex(at: 0.74) == 0, "Salto atrás")
        expect(Lyrics(lrc: "[ar:Autor]\nSolo texto").plainText == "Solo texto", "Letra sin sincronización")
        expect(Lyrics().isEmpty, "Sin letra")

        let extended = Lyrics(lrc: "[00:01][00:06]<00:01>Hola <00:01.50>mundo<00:02.25>")
        expect(extended.lines[1].text == "Hola mundo", "Texto de LRC extendido")
        expect(extended.lines[1].words[0].text == "Hola ", "Conservar espacios")
        expect(extended.lines[1].wordIndex(at: 1.499) == 0, "Palabra vigente")
        expect(extended.lines[1].wordIndex(at: 1.5) == 1, "Límite de palabra")
        expect(extended.lines[2].words[1].end == 7.25, "Marca final de línea repetida")
        expect(Lyrics(lrc: "[00:01]<00:02>fin").lines[1].words[0].end == nil, "Final desconocido")
        expect(Lyrics(lrc: "[00:01]<00:03>dos <00:02>uno").lines[1].words.isEmpty, "Marcas fuera de orden")

        let source = """
        version: '1.0'
        lines:
          - text: "Dos palabras"
            start_ms: 1000
            end_ms: 3000
            words:
              - text: 'Dos '
                start_ms: 1100
                end_ms: 2000
              - text: palabras
                start_ms: 2100
          - text: Vuelve
            start_ms: 5000
        plain: |
          Dos palabras
        """
        let timed = Lyrics(timedLines: LyricsfileTiming.parse(source))
        expect(timed.lines[1].words[0].end == 2, "Lyricsfile con final explícito")
        expect(timed.lines[timed.lineIndex(at: 4)!].isInstrumental, "Pausa con final explícito")
        expect(timed.lines[timed.lineIndex(at: 5)!].text == "Vuelve", "Reanudación tras la pausa musical")
    }

    private static func checkSettings() throws {
        let old = #"{"version":1,"theme":"system","accentMode":"artwork","translucent":true,"visualizer":"bars","cacheEnabled":true,"audioEnabled":false,"audioProfile":"balanced","shortcuts":{}}"#
        let settings = try JSONDecoder().decode(MusicSettings.self, from: Data(old.utf8))
        expect(settings.lyricsFollow == nil && settings.lyricsOffsets == nil, "Configuración anterior")
        expect(settings.lyricsScrollMetadata == nil && settings.lyricsActiveTextAccent == nil,
               "Preferencias de presentación ausentes en una configuración anterior")
        var updated = settings
        updated.lyricsScrollMetadata = true
        updated.lyricsActiveTextAccent = false
        let roundTrip = try JSONDecoder().decode(MusicSettings.self, from: JSONEncoder().encode(updated))
        expect(roundTrip.lyricsScrollMetadata == true && roundTrip.lyricsActiveTextAccent == false,
               "Preferencias de presentación conservadas al exportar e importar")
        let one = LyricsOffsets.updating(Data(), trackID: "A", steps: -2)
        let two = LyricsOffsets.updating(one, trackID: "B", steps: 3)
        let reset = LyricsOffsets.updating(two, trackID: "A", steps: 0)
        expect(LyricsOffsets.steps(in: two, trackID: "A") == -2, "Desfase independiente")
        expect(LyricsOffsets.steps(in: reset, trackID: "A") == 0 && LyricsOffsets.steps(in: reset, trackID: "B") == 3,
               "Restablecer solo una canción")
    }

    @MainActor
    private static func checkStore() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let directory = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockLyricsHTTP.self]
        let store = LyricsStore(directory: directory, session: URLSession(configuration: config))

        func track(_ title: String) -> Track {
            Track(url: root.appendingPathComponent(title).appendingPathExtension("mp3"),
                  title: title, artist: "Autora", album: "Álbum", duration: 120, mtime: 1, loaded: true)
        }
        let local = track("local")
        try Data("Texto local".utf8).write(to: local.url.deletingPathExtension().appendingPathExtension("lrc"))
        let result = try await store.lyrics(for: local, duration: 120)
        expect(result.hasLyrics, "Preferencia de .lrc local sin timestamps")

        let now = Date(timeIntervalSince1970: 0)
        expect(LyricsStore.retryDate("30", now: now, fallback: 5).timeIntervalSince1970 == 30, "Retry-After segundos")
        expect(LyricsStore.retryDate("Thu, 01 Jan 1970 00:00:40 GMT", now: now, fallback: 5)
            .timeIntervalSince1970 == 40, "Retry-After fecha")

        let remix = track("Tema (Remix)")
        let fields = [remix.id, String(remix.mtime), remix.title, remix.artist, remix.album].joined(separator: "\u{0}")
        let key = SHA256.hash(data: Data(fields.utf8)).map { String(format: "%02x", $0) }.joined()
        try Data("incompleto".utf8).write(to: directory.appendingPathComponent(key + ".js"))
        MockLyricsHTTP.response = { request in
            if request.url?.path == "/api/search" {
                return .init(status: 200, body: """
                [{"trackName":"Tema","artistName":"Otra","duration":120,"instrumental":false,"plainLyrics":"mal artista"},
                 {"trackName":"Tema","artistName":"Autora","duration":150,"instrumental":false,"plainLyrics":"mal tiempo"},
                 {"trackName":"Tema","artistName":"Autora","duration":121,"instrumental":false,"plainLyrics":"correcta"}]
                """)
            }
            return .init(status: 404)
        }
        let match = try await store.lyrics(for: remix, duration: 120, requireOfflineCopy: true)
        if case let .lyrics(lyrics) = match { expect(lyrics.plainText == "correcta", "Validación de búsqueda alternativa") }
        else { fatalError("Faltó la coincidencia alternativa") }

        MockLyricsHTTP.response = { _ in .init(status: 404) }
        let missing = track("Ausente")
        _ = try await store.lyrics(for: missing, duration: 120)
        MockLyricsHTTP.response = { _ in .init(status: 429, headers: ["Retry-After": "1"]) }
        _ = try await store.lyrics(for: missing, duration: 120)
        do {
            _ = try await store.lyrics(for: missing, duration: 120, refresh: true)
            fatalError("Faltó la respuesta 429")
        } catch LyricsStore.LookupError.rateLimited {}

        let disconnected = track("Sin conexión")
        MockLyricsHTTP.response = { _ in .init(status: 0, error: URLError(.notConnectedToInternet)) }
        let waitForCooldown = Task {
            try await store.lyrics(for: disconnected, duration: 120, requireOfflineCopy: true)
        }
        do {
            _ = try await waitForCooldown.value
            fatalError("Faltó el error de conexión")
        } catch let error as URLError {
            expect(error.code == .notConnectedToInternet, "Error de conexión individual")
        }
        MockLyricsHTTP.response = { request in
            let title = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "track_name" })?.value
            return title == "Error" ? .init(status: 503, headers: ["Retry-After": "0"]) : .init(status: 404)
        }
        let sync = LyricsSync(store: store)
        sync.start([track("Error"), remix])
        while sync.isRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        expect(sync.progress?.failed == 1 && sync.progress?.available == 1 && sync.progress?.pending == 0,
               "Continuación después de agotar reintentos")
        sync.start([track("Error"), remix])
        sync.cancel()
        while sync.isRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        expect(sync.progress?.pending == 2, "Cancelación conserva pendientes")
        sync.start([remix, missing])
        while sync.isRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        expect(sync.progress?.available == 1 && sync.progress?.failed == 0, "Reanudar reutiliza las copias")
    }
}
