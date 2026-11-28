import AVFoundation
import Foundation
import Darwin

@main
enum MetadataChecks {
    private struct SimulatedFailure: Error {}

    private static let portrait = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7wAAAABJRU5ErkJggg==")!
    private static let recording = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private static let alternate = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private static let release = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private static let remaster = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

    static func main() async {
        do { try await run() }
        catch {
            let detail = error as NSError
            fputs("Falló la prueba: \(detail.domain) (\(detail.code)) \(detail.localizedDescription) \(detail.userInfo)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let wav = work.appendingPathComponent("synthetic.wav")
        print("Preparando audio sintético…")
        try sine(to: wav, seconds: 4)
        let flac = work.appendingPathComponent("synthetic.flac")
        let m4a = work.appendingPathComponent("synthetic.m4a")
        try convert(wav, to: flac, format: "flac", codec: "flac")
        try convert(wav, to: m4a, format: "m4af", codec: "aac ")

        let mp3 = work.appendingPathComponent("synthetic.mp3")
        try mp3Silence().write(to: mp3)
        let tagged = work.appendingPathComponent("tagged-v23.mp3")
        let lyric = Data("Letra sintética preservada".utf8)
        let comment = Data("Comentario ajeno preservado".utf8)
        let frames = id3Frame("USLT", lyric) + id3Frame("COMM", comment)
        let header = Data([73, 68, 51, 3, 0, 0, 0, 0, UInt8(frames.count >> 7), UInt8(frames.count & 127)])
        try (header + frames + mp3Silence()).write(to: tagged)

        // Exercise the transaction, metadata parsing and reproducible decoding for each container.
        for file in [mp3, flac, m4a] {
            print("Comprobando \(file.pathExtension)…")
            try await checkEditing(file)
        }
        print("Comprobando cancelación y restauración…")
        try await checkEditing(tagged)
        let taggedData = try Data(contentsOf: tagged)
        try expect(taggedData.range(of: id3Frame("USLT", lyric)) != nil &&
                   taggedData.range(of: id3Frame("COMM", comment)) != nil,
                   "letras y comentarios ID3v2.3 conservados byte a byte")
        try await checkFailures(in: work, valid: flac)
        try await checkRecognition(work: work, audio: wav)
        print("OK: MP3, FLAC, M4A, portadas, conservación de etiquetas, audio, permisos, cancelación, recuperación y respuestas de red simuladas.")
    }

    private static func checkEditing(_ file: URL) async throws {
        let baseline = try decoded(file)
        let cover = MetadataCover(data: portrait, mime: "image/png", width: 1, height: 1, depth: 16)
        let changes: [MusicTag: String] = [
            .title: "Canción sintética", .artist: "Intérprete", .albumArtist: "Conjunto",
            .genre: "Instrumental", .year: "2020", .track: "2/12",
            .recording: recording.uuidString.lowercased(), .release: release.uuidString.lowercased()
        ]
        let original = try Data(contentsOf: file)
        let first = try await MetadataWriter.write(to: file, expected: MetadataWriter.revision(file),
                                                   changes: changes, cover: cover)
        try expect(Data(contentsOf: first) == original, "la copia conserva el original")
        try expect(MetadataWriter.readTags(file) == changes, "etiquetas persistentes de \(file.pathExtension)")
        try expect(decoded(file) == baseline, "audio intacto de \(file.pathExtension)")
        if file.pathExtension == "flac" {
            try expect(MetadataWriter.flacLibraryTags(for: file)[.title] == changes[.title],
                       "lectura de etiquetas FLAC durante el escaneo de biblioteca")
        } else {
            let exposedTitle = AVURLAsset(url: file).commonMetadata.first { $0.commonKey == .commonKeyTitle }?.stringValue
            try expect(exposedTitle == changes[.title], "lectura de etiquetas de biblioteca mediante AVFoundation")
        }
        try expect(Data(contentsOf: file).range(of: portrait) != nil, "portada incrustada")
        let verified = try Data(contentsOf: file)
        let second = try await MetadataWriter.write(to: file, expected: MetadataWriter.revision(file),
                                                    changes: [.album: "Edición remasterizada"], cover: nil)
        try expect(Data(contentsOf: second) == verified, "copia de archivo ya etiquetado")
        try expect(MetadataWriter.readTags(file) == changes.merging([.album: "Edición remasterizada"]) { _, new in new },
                   "conservación de campos no seleccionados")
        try expect(Data(contentsOf: file).range(of: portrait) != nil, "portada sin editar")
        try expect(decoded(file) == baseline, "reproducción tras un segundo guardado")
    }

    private static func checkFailures(in work: URL, valid: URL) async throws {
        let bytes = try Data(contentsOf: valid)
        let oldVersion = try MetadataWriter.revision(valid)
        let readonly = work.appendingPathComponent("readonly.flac")
        try bytes.write(to: readonly)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readonly.path)
        try await expectFailure("archivo de solo lectura") {
            _ = try await MetadataWriter.write(to: readonly, expected: MetadataWriter.revision(readonly),
                                               changes: [.title: "Cambiar"], cover: nil)
        }
        let corrupt = work.appendingPathComponent("bad.mp3")
        try Data(repeating: 0xff, count: 4096).write(to: corrupt)
        try await expectFailure("archivo corrupto") {
            _ = try await MetadataWriter.write(to: corrupt, expected: MetadataWriter.revision(corrupt),
                                               changes: [.title: "Cambiar"], cover: nil)
        }
        try await expectFailure("cancelación antes de sustituir") {
            _ = try await MetadataWriter.write(to: valid, expected: oldVersion, changes: [.title: "Cambiar"],
                                               cover: nil, beforeCommit: { throw CancellationError() })
        }
        try expect(Data(contentsOf: valid) == bytes, "el archivo se conserva al cancelar")
        try await expectFailure("error tras sustituir") {
            _ = try await MetadataWriter.write(to: valid, expected: oldVersion, changes: [.title: "Cambiar"],
                                               cover: nil, verifyInstallation: { throw SimulatedFailure() })
        }
        try expect(Data(contentsOf: valid) == bytes, "restauración del original")
        try expect(MetadataWriter.revision(valid) == oldVersion, "se restauró el mismo archivo")
        try await expectFailure("revisión obsoleta") {
            _ = try await MetadataWriter.write(to: valid, expected: MetadataWriter.revision(readonly),
                                               changes: [.title: "Cambiar"], cover: nil)
        }
    }

    private static func checkRecognition(work: URL, audio: URL) async throws {
        let key = "fixture-client"
        let service = OnlineMusicIdentification(fingerprinting: FixtureFingerprint(), clientKey: key) { request, _, cover in
            guard let url = request.url else { throw SimulatedFailure() }
            if url.host == "api.acoustid.org" {
                try expect(request.httpMethod == "POST", "consulta por POST")
                let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                try expect(body.contains("fingerprint=fixture") && body.contains("duration=185") &&
                           body.contains("client=fixture-client") && body.contains("user=fixture-user"),
                           "la consulta usa la huella, duración y claves")
                return matchesJSON
            }
            if cover {
                if url.path.contains(remaster.uuidString.lowercased()) { throw HTTPFailure(status: 404) }
                return portrait
            }
            if url.path.hasSuffix("/release") { return releasesJSON }
            return Data(#"{"genres":[{"name":"rock","count":2}]}"#.utf8)
        }
        let matches = try await service.identify(audio, userKey: "fixture-user")
        try expect(matches.map(\.id) == [recording, alternate], "candidatos similares deduplicados y ordenados por puntuación")
        let editions = try await service.editions(for: recording)
        try expect(editions.map(\.releaseID) == [release, remaster], "edición original y remasterizadas separadas")
        try expect(editions.last?.detail.contains("Remasterizado") == true, "desambiguación de edición")
        try expect(editions.last?.tags[.genre] == "rock", "género de MusicBrainz")
        let art = try await service.cover(for: release)
        try expect(art?.mime == "image/png" && art?.width == 1, "portada validada")
        let missing = try await service.cover(for: remaster)
        try expect(missing == nil, "portada inexistente")

        let empty = OnlineMusicIdentification(fingerprinting: FixtureFingerprint(), clientKey: key) { _, _, _ in
            Data(#"{"status":"ok","results":[]}"#.utf8)
        }
        let noMatches = try await empty.identify(audio, userKey: "")
        try expect(noMatches.isEmpty, "sin coincidencias")
        let offline = OnlineMusicIdentification(fingerprinting: FixtureFingerprint(), clientKey: key) { _, _, _ in
            throw URLError(.notConnectedToInternet)
        }
        try await expectFailure("sin conexión") { _ = try await offline.identify(audio, userKey: "") }
        let interrupted = OnlineMusicIdentification(fingerprinting: FixtureFingerprint(), clientKey: key) { _, _, _ in
            throw URLError(.networkConnectionLost)
        }
        try await expectFailure("portada interrumpida") { _ = try await interrupted.cover(for: release) }

        let slow = OnlineMusicIdentification(fingerprinting: FixtureFingerprint(waitForCancellation: true), clientKey: key) { _, _, _ in
            fatalError("La cancelación de la huella no debe iniciar una consulta")
        }
        let job = Task { try await slow.identify(audio, userKey: "") }
        try await Task.sleep(nanoseconds: 15_000_000)
        job.cancel()
        do { _ = try await job.value; throw SimulatedFailure() }
        catch is CancellationError { }

        let path = CommandLine.arguments[2]
        if !path.isEmpty {
            let library = URL(fileURLWithPath: path).appendingPathComponent("libchromaprint.dylib")
            let benchmark = work.appendingPathComponent("benchmark.wav")
            try sine(to: benchmark, seconds: 120)
            let engine = ChromaprintFingerprinting(libraryURL: library)
            for run in 1...3 { try measure(engine: engine, audio: benchmark, run: run) }
        }
    }

    private static func measure(engine: ChromaprintFingerprinting, audio: URL, run: Int) throws {
        let rssBefore = residentMiB()
        let sampler = DispatchQueue(label: "musicalocal.tests.memory")
        let timer = DispatchSource.makeTimerSource(queue: sampler)
        var peak = rssBefore
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { peak = max(peak, residentMiB()) }
        timer.resume()
        defer { timer.cancel() }
        let wall = DispatchTime.now().uptimeNanoseconds
        let cpuBefore = cpuSeconds()
        let result = try engine.fingerprint(for: audio)
        let cpu = cpuSeconds() - cpuBefore
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - wall) / 1e9
        let rssAfter = residentMiB()
        timer.cancel()
        let sampledPeak = sampler.sync { max(peak, rssAfter) }
        try expect(result.duration == 120 && result.value.count > 30, "huella acústica local real")
        print(String(format: "Chromaprint %d/3 (120 s WAV mono): %.3f s reales, %.3f s CPU; RSS %.1f / %.1f / %.1f MiB antes / pico / después.",
                     run, elapsed, cpu, rssBefore, sampledPeak, rssAfter))
    }

    private struct FixtureFingerprint: AcousticFingerprinting {
        var waitForCancellation = false
        func fingerprint(for url: URL) throws -> AcousticFingerprint {
            while waitForCancellation {
                try Task.checkCancellation()
                Thread.sleep(forTimeInterval: 0.001)
            }
            return AcousticFingerprint(value: "fixture", duration: 185)
        }
    }

    private static let matchesJSON = Data(#"""
    {"status":"ok","results":[
      {"score":0.72,"recordings":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","title":"Tema (directo)","duration":190,"artists":[{"name":"Artista"}]}]},
      {"score":0.97,"recordings":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","title":"Tema","duration":184,"artists":[{"name":"Artista"}]}]},
      {"score":0.45,"recordings":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","title":"Tema","duration":184,"artists":[{"name":"Artista"}]}]},
      {"score":0.99,"recordings":[{"id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","title":"Tema","duration":280,"artists":[{"name":"Artista"}]}]}
    ]}
    """#.utf8)

    private static var releasesJSON: Data {
        let rows = [release, remaster].enumerated().map { index, id in
            """
            {"id":"\(id)","title":"Álbum","date":"202\(index)","disambiguation":"\(index == 1 ? "Remasterizado" : "Original")",
            "artist-credit":[{"name":"Artista"}],"media":[{"position":1,"format":"CD","tracks":[
            {"id":"\(UUID())","position":2,"number":"2","recording":{"id":"\(recording)","title":"Tema","artist-credit":[{"name":"Artista"}]}}
            ]}]}
            """
        }
        return Data(("{\"release-count\":2,\"releases\":[" + rows.joined(separator: ",") + "]}").utf8)
    }

    private static func sine(to url: URL, seconds: Int) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let audio = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        let samples = buffer.floatChannelData![0]
        for index in 0..<44_100 {
            samples[index] = Float(sin(2 * .pi * 440 * Double(index) / 44_100)) * 0.2
        }
        for _ in 0..<seconds { try audio.write(from: buffer) }
    }

    private static func convert(_ source: URL, to dest: URL, format: String, codec: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", format, "-d", codec, source.path, dest.path]
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "generación de archivo \(format)")
    }

    private static func id3Frame(_ id: String, _ content: Data) -> Data {
        // ID3v2.3 uses ISO-8859-1 for encoding 0 and a 32-bit big-endian size.
        let text = String(decoding: content, as: UTF8.self).data(using: .isoLatin1)!
        let payload = Data([0, 101, 110, 103, 0]) + text
        return Data(id.utf8) + Data([0, 0, 0, UInt8(payload.count), 0, 0]) + payload
    }

    private static func mp3Silence() -> Data {
        let frame = Data([0xff, 0xfb, 0x90, 0xc0]) + Data(repeating: 0, count: 413)
        return (0..<150).reduce(into: Data()) { data, _ in data.append(frame) }
    }

    private static func decoded(_ url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192)!
        var data = Data()
        let length = file.length
        while file.framePosition < length {
            do { try file.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, length - file.framePosition))) }
            catch { throw MetadataError("Lectura de \(url.pathExtension) falló en \(file.framePosition) de \(length) cuadros: \(error)") }
            if buffer.frameLength == 0 { break }
            let samples = buffer.int16ChannelData![0]
            data.append(Data(bytes: samples, count: Int(buffer.frameLength) * Int(buffer.format.channelCount) * 2))
        }
        try expect(!data.isEmpty, "audio decodificado")
        return data
    }

    private static func residentMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return Double(info.resident_size) / 1_048_576
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
            Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private static func expect(_ test: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try test() else { throw MetadataError("Prueba fallida: \(message)") }
    }

    private static func expectFailure(_ message: String, _ test: () async throws -> Void) async throws {
        do { try await test() } catch { return }
        throw MetadataError("Se esperaba un fallo: \(message)")
    }
}
