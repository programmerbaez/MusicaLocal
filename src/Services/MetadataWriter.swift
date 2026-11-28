import AVFoundation
import CryptoKit
import Foundation
import Darwin

enum MusicTag: String, CaseIterable, Identifiable {
    case title = "TITLE", artist = "ARTIST", album = "ALBUM", albumArtist = "ALBUMARTIST"
    case year = "DATE", genre = "GENRE", track = "TRACKNUMBER", disc = "DISCNUMBER"
    case recording = "MUSICBRAINZ_TRACKID", release = "MUSICBRAINZ_ALBUMID"

    var id: Self { self }
    var label: String {
        switch self {
        case .title: return "Título"
        case .artist: return "Artista"
        case .album: return "Álbum"
        case .albumArtist: return "Artista del álbum"
        case .year: return "Año o fecha"
        case .genre: return "Género"
        case .track: return "Número de pista"
        case .disc: return "Número de disco"
        case .recording: return "ID de grabación MusicBrainz"
        case .release: return "ID de publicación MusicBrainz"
        }
    }
}

struct MetadataError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct MetadataCover {
    let data: Data
    let mime: String
    let width: Int
    let height: Int
    let depth: Int
}

private struct FLACMetadata {
    struct Block: Equatable {
        let type: UInt8
        let data: Data
        var front: Bool { type == 6 && data.prefix(4) == Data([0, 0, 0, 3]) }
    }

    static let magic = Data("fLaC".utf8)
    var blocks: [Block]
    var comments: Comments

    static func read(_ handle: FileHandle) throws -> Self {
        guard try handle.read(upToCount: 4) == magic else { throw invalid }
        var blocks: [Block] = []
        var total = 0
        while true {
            let header = try readExact(handle, count: 4)
            let type = header[0] & 127
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            total += size + 4
            guard type < 127, total <= 32 * 1024 * 1024, blocks.count < 1024,
                  blocks.isEmpty ? (type == 0 && size == 34) : type != 0 else { throw invalid }
            blocks.append(Block(type: type, data: try readExact(handle, count: size)))
            if header[0] & 128 != 0 { break }
        }
        let commentBlocks = blocks.filter { $0.type == 4 }
        guard commentBlocks.count <= 1 else { throw invalid }
        let comments = try commentBlocks.first.map { try Comments(data: $0.data) } ?? Comments()
        return Self(blocks: blocks, comments: comments)
    }

    // La biblioteca solo necesita el comentario Vorbis. Omite las carátulas y
    // otros bloques sin cargarlos durante el escaneo habitual.
    static func libraryTags(_ handle: FileHandle) throws -> [MusicTag: String] {
        guard try handle.read(upToCount: 4) == magic else { throw invalid }
        for _ in 0..<1024 {
            let header = try readExact(handle, count: 4)
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if header[0] & 127 == 4 { return try Comments(data: readExact(handle, count: size)).values }
            if header[0] & 128 != 0 { return [:] }
            try handle.seek(toOffset: try handle.offset() + UInt64(size))
        }
        throw invalid
    }

    static let invalid = MetadataError("El archivo FLAC está dañado o contiene una estructura de etiquetas no compatible.")

    private static func readExact(_ handle: FileHandle, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        guard let data = try handle.read(upToCount: count), data.count == count else { throw invalid }
        return data
    }

    struct Comments {
        var vendor = Data("MusicaLocal".utf8)
        var entries: [Data] = []

        init() {}

        init(data: Data) throws {
            var position = 0
            func integer() throws -> Int {
                guard position + 4 <= data.count else { throw FLACMetadata.invalid }
                defer { position += 4 }
                return (0..<4).reduce(0) { $0 | Int(data[position + $1]) << (8 * $1) }
            }
            func field() throws -> Data {
                let size = try integer()
                guard size <= data.count - position else { throw FLACMetadata.invalid }
                defer { position += size }
                return data.subdata(in: position..<(position + size))
            }
            vendor = try field()
            let count = try integer()
            guard count <= 50_000, count <= (data.count - position) / 4 else { throw FLACMetadata.invalid }
            for _ in 0..<count { entries.append(try field()) }
            guard position == data.count else { throw FLACMetadata.invalid }
        }

        static func key(_ entry: Data) -> String {
            String(decoding: entry.prefix { $0 != 61 }, as: UTF8.self).uppercased()
        }

        var values: [MusicTag: String] {
            entries.reduce(into: [:]) { values, entry in
                guard let equals = entry.firstIndex(of: 61), let tag = MusicTag(rawValue: Self.key(entry)),
                      values[tag] == nil else { return }
                values[tag] = String(data: entry.suffix(from: equals + 1), encoding: .utf8)
            }
        }

        mutating func update(_ changes: [MusicTag: String]) {
            entries.removeAll { MusicTag(rawValue: Self.key($0)).flatMap { changes[$0] } != nil }
            for tag in MusicTag.allCases {
                if let value = changes[tag] { entries.append(Data("\(tag.rawValue)=\(value)".utf8)) }
            }
        }

        var data: Data {
            var result = Data()
            func append(_ field: Data) {
                result.appendInteger(field.count, littleEndian: true)
                result.append(field)
            }
            append(vendor)
            result.appendInteger(entries.count, littleEndian: true)
            for entry in entries { append(entry) }
            return result
        }
    }

    mutating func update(_ changes: [MusicTag: String], cover: MetadataCover?) {
        if !changes.isEmpty {
            comments.update(changes)
            let block = Block(type: 4, data: comments.data)
            if let index = blocks.firstIndex(where: { $0.type == 4 }) { blocks[index] = block }
            else { blocks.insert(block, at: 1) }
        }
        if let cover = cover {
            var data = Data()
            let mime = Data(cover.mime.utf8)
            data.appendInteger(3)
            data.appendInteger(mime.count)
            data.append(mime)
            for number in [0, cover.width, cover.height, cover.depth, 0, cover.data.count] {
                data.appendInteger(number)
            }
            data.append(cover.data)
            let firstPicture = blocks.firstIndex(where: { $0.type == 6 }) ?? blocks.count
            blocks.removeAll(where: \.front)
            blocks.insert(Block(type: 6, data: data), at: firstPicture)
        }
    }

    func write(to handle: FileHandle) throws {
        try handle.write(contentsOf: Self.magic)
        for (index, block) in blocks.enumerated() {
            let size = block.data.count
            guard size < 1 << 24 else { throw Self.invalid }
            let type = block.type | (index == blocks.count - 1 ? 128 : 0)
            try handle.write(contentsOf: Data([type, UInt8(size >> 16),
                                               UInt8(truncatingIfNeeded: size >> 8), UInt8(truncatingIfNeeded: size)]))
            try handle.write(contentsOf: block.data)
        }
    }
}

private extension Data {
    mutating func appendInteger(_ value: Int, littleEndian: Bool = false) {
        let shifts = littleEndian ? [0, 8, 16, 24] : [24, 16, 8, 0]
        append(contentsOf: shifts.map { UInt8(truncatingIfNeeded: value >> $0) })
    }
}

private enum EditableMusicMetadata {
    case flac(FLACMetadata)
    case mp3(ID3Metadata)
    case m4a(M4AMetadata)

    static func read(_ handle: FileHandle, extension ext: String) throws -> Self {
        switch ext {
        case "flac": return .flac(try FLACMetadata.read(handle))
        case "mp3": return .mp3(try ID3Metadata.read(handle))
        case "m4a": return .m4a(try M4AMetadata.read(handle))
        default: throw MetadataError("La edición no está disponible para este formato.")
        }
    }

    var values: [MusicTag: String] {
        switch self {
        case let .flac(meta): return meta.comments.values
        case let .mp3(meta): return meta.values
        case let .m4a(meta): return meta.values
        }
    }

    mutating func update(_ changes: [MusicTag: String], cover: MetadataCover?) throws {
        switch self {
        case var .flac(meta):
            meta.update(changes, cover: cover)
            self = .flac(meta)
        case var .mp3(meta):
            try meta.update(changes, cover: cover)
            self = .mp3(meta)
        case var .m4a(meta):
            try meta.update(changes, cover: cover)
            self = .m4a(meta)
        }
    }

    func write(to handle: FileHandle) throws {
        switch self {
        case let .flac(meta): try meta.write(to: handle)
        case let .mp3(meta): try meta.write(to: handle)
        case let .m4a(meta): try meta.write(to: handle)
        }
    }

    func verifies(_ other: Self) -> Bool {
        switch (self, other) {
        case let (.flac(a), .flac(b)): return a.blocks == b.blocks
        case let (.mp3(a), .mp3(b)): return a.verifies(b)
        case let (.m4a(a), .m4a(b)): return a.verifies(b)
        default: return false
        }
    }
}

enum MetadataWriter {
    static func supports(_ url: URL) -> Bool { ["flac", "mp3", "m4a"].contains(url.pathExtension.lowercased()) }

    static func readTags(_ url: URL) throws -> [MusicTag: String] {
        guard supports(url) else { throw MetadataError("Edición no disponible para este formato.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try EditableMusicMetadata.read(handle, extension: url.pathExtension.lowercased()).values
    }

    static func flacLibraryTags(for url: URL) -> [MusicTag: String] {
        guard let input = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? input.close() }
        return (try? FLACMetadata.libraryTags(input)) ?? [:]
    }

    /// Devuelve la copia de recuperación. Se conserva junto al original después de guardar.
    struct Revision: Equatable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let seconds: Int
        let nanoseconds: Int
    }

    static func revision(_ url: URL) throws -> Revision { revision(try identity(url)) }

    private static func revision(_ info: stat) -> Revision {
        Revision(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                 seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec)
    }

    static func write(to url: URL, expected: Revision, changes: [MusicTag: String], cover: MetadataCover?,
                      beforeCommit: @MainActor () throws -> Void = {},
                      verifyInstallation: () throws -> Void = {}) async throws -> URL {
        guard supports(url) else { throw MetadataError("La escritura segura está disponible para archivos FLAC, MP3 y M4A compatibles.") }
        guard !changes.isEmpty || cover != nil,
              changes.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                           !$0.contains("\0") && $0.utf8.count <= 4096 }) else {
            throw MetadataError("Selecciona cambios válidos. Cada etiqueta admite hasta 4096 bytes.")
        }
        let ext = url.pathExtension.lowercased()
        let invalidAudio = MetadataError("No se pudo verificar la integridad del audio o las etiquetas escritas.")
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        let original = try identity(url)
        guard expected == revision(original) else { throw MetadataError("El archivo cambió. Cierra y vuelve a abrir el editor.") }
        guard original.st_mode & S_IFMT == S_IFREG, original.st_nlink == 1,
              original.st_mode & 0o222 != 0, fm.isWritableFile(atPath: url.path),
              fm.isWritableFile(atPath: directory.path) else {
            throw MetadataError("El archivo o su carpeta no permiten un reemplazo seguro.")
        }
        let available = try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        guard Int64(available) > original.st_size + Int64(cover?.data.count ?? 0) + 65_536 else {
            throw MetadataError("No hay espacio suficiente para preparar la copia de trabajo.")
        }

        let recovery = directory.appendingPathComponent(".musicalocal-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: recovery, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        let staged = recovery.appendingPathComponent(UUID().uuidString + "." + ext)
        let backup = recovery.appendingPathComponent(url.lastPathComponent)
        var keepBackup = false
        defer { if !keepBackup { try? fm.removeItem(at: recovery) } }

        let formats = ["flac": kAudioFileFLACType, "mp3": kAudioFileMP3Type, "m4a": kAudioFileM4AType]
        guard let format = formats[ext] else { throw invalidAudio }
        try verifyFormat(url, type: format)
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var metadata = try EditableMusicMetadata.read(input, extension: ext)
        if case .m4a = metadata {
            try input.seek(toOffset: 0)
        } else if try input.offset() >= UInt64(original.st_size) {
            throw invalidAudio
        }
        var originalHash = SHA256()
        try metadata.update(changes, cover: cover)
        guard fm.createFile(atPath: staged.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw MetadataError("No se pudo crear la copia de trabajo.")
        }
        let output = try FileHandle(forWritingTo: staged)
        do {
            if case let .m4a(movie) = metadata {
                try transfer(input, through: movie.movieOffset, to: output, hash: &originalHash)
                if movie.movieEnd < movie.fileSize {
                    try input.seek(toOffset: movie.movieEnd)
                    try movie.reserveOriginalMovie(in: output)
                    try transfer(input, through: movie.fileSize, to: output, hash: &originalHash)
                }
                try metadata.write(to: output)
            } else {
                try metadata.write(to: output)
                try transfer(input, through: UInt64(original.st_size), to: output, hash: &originalHash)
            }
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        let check = try FileHandle(forReadingFrom: staged)
        defer { try? check.close() }
        let verified = try EditableMusicMetadata.read(check, extension: ext)
        var stagedHash = SHA256()
        if case let .m4a(movie) = metadata {
            try check.seek(toOffset: 0)
            try transfer(check, through: movie.movieOffset, to: nil, hash: &stagedHash)
            if movie.movieEnd < movie.fileSize {
                try check.seek(toOffset: movie.movieEnd)
                try transfer(check, through: movie.fileSize, to: nil, hash: &stagedHash)
            }
        } else {
            try transfer(check, through: try check.seekToEndPreservingOffset(), to: nil, hash: &stagedHash)
        }
        guard metadata.verifies(verified), metadata.values == verified.values,
              originalHash.finalize() == stagedHash.finalize() else { throw invalidAudio }
        // AVFoundation comprueba que el contenedor editado sigue siendo legible.
        try verifyFormat(staged, type: format)
        let audio = try AVAudioFile(forReading: staged)
        guard audio.length > 0,
              let probe = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096) else {
            throw invalidAudio
        }
        try audio.read(into: probe)
        guard probe.frameLength > 0 else { throw invalidAudio }

        try Task.checkCancellation()
        guard same(original, try identity(url)),
              copyfile(url.path, staged.path, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw MetadataError("El archivo cambió o no se pudieron preservar sus atributos.")
        }
        let previousSecond = TimeInterval(original.st_mtimespec.tv_sec)
        let now = Date().timeIntervalSince1970
        let newDate = Date(timeIntervalSince1970: Int(now) == Int(previousSecond) ? previousSecond + 1 : now)
        try fm.setAttributes([.modificationDate: newDate], ofItemAtPath: staged.path)
        let stagedFD = try FileHandle(forUpdating: staged)
        try stagedFD.synchronize()
        try stagedFD.close()
        let stagedIdentity = try identity(staged)
        guard stagedIdentity.st_uid == original.st_uid, stagedIdentity.st_gid == original.st_gid,
              stagedIdentity.st_mode == original.st_mode else {
            throw MetadataError("No se pudieron conservar el propietario o los permisos originales.")
        }
        guard link(url.path, backup.path) == 0 else {
            throw MetadataError("No se pudo crear la copia de recuperación.")
        }
        try synchronizeDirectory(recovery)
        try synchronizeDirectory(directory)
        // El enlace de seguridad comparte el original, pero no su nombre visible.
        guard same(original, try identity(backup)), same(original, try identity(url)) else {
            throw MetadataError("El archivo cambió durante la preparación.")
        }
        try await beforeCommit()
        try Task.checkCancellation()
        guard same(original, try identity(url)) else {
            throw MetadataError("El archivo cambió antes de sustituirlo.")
        }
        guard rename(staged.path, url.path) == 0 else {
            throw MetadataError("No se pudo sustituir el archivo. Se conserva el original.")
        }
        keepBackup = true
        do {
            guard same(stagedIdentity, try identity(url)) else {
                throw MetadataError("El archivo cambió tras instalar las etiquetas.")
            }
            try verifyInstallation()
            try synchronizeDirectory(directory)
            try synchronizeDirectory(recovery)
        } catch {
            if let installed = try? identity(url), same(stagedIdentity, installed), rename(backup.path, url.path) == 0 {
                keepBackup = false
                try? synchronizeDirectory(directory)
                throw MetadataError("El guardado falló y se restauró el original.")
            }
            throw MetadataError("No se pudo restaurar automáticamente. Copia de recuperación en \(backup.path)")
        }
        return backup
    }

    private static func transfer(_ input: FileHandle, through end: UInt64,
                                 to output: FileHandle?, hash: inout SHA256) throws {
        let position = try input.offset()
        guard position <= end else { throw MetadataError("El tamaño del archivo cambió durante la operación.") }
        var remaining = end - position
        while remaining > 0 {
            try Task.checkCancellation()
            let count = Int(min(remaining, 256 * 1024))
            guard let data = try input.read(upToCount: count), !data.isEmpty else {
                throw MetadataError("No se pudo leer el contenido completo del archivo de audio.")
            }
            remaining -= UInt64(data.count)
            hash.update(data: data)
            try output?.write(contentsOf: data)
        }
    }

    private static func verifyFormat(_ url: URL, type: AudioFileTypeID) throws {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file = file else {
            throw MetadataError("El archivo no contiene audio compatible.")
        }
        defer { AudioFileClose(file) }
        var actual: AudioFileTypeID = 0
        var size = UInt32(MemoryLayout<AudioFileTypeID>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyFileFormat, &size, &actual) == noErr, actual == type else {
            throw MetadataError("El contenido de audio no coincide con la extensión del archivo.")
        }
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { throw MetadataError("No se pudo verificar el guardado en disco.") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw MetadataError("No se pudo verificar el guardado en disco.") }
    }

    private static func identity(_ url: URL) throws -> stat {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw MetadataError("No se pudo acceder al archivo.") }
        return info
    }

    private static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
    }
}

private extension FileHandle {
    func seekToEndPreservingOffset() throws -> UInt64 {
        let previous = try offset()
        let end = try seekToEnd()
        try seek(toOffset: previous)
        return end
    }
}
