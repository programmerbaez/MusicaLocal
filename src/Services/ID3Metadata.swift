import Foundation

/// ID3v2 tags at the beginning of standard MP3 files. Other layouts are rejected.
struct ID3Metadata {
    private struct Frame: Equatable {
        let id: String
        let flags: Data
        let data: Data
    }

    static let invalid = MetadataError("El archivo MP3 está dañado o utiliza una variante de ID3 que este editor no puede modificar con seguridad.")
    private static let names: [MusicTag: String] = [
        .title: "TIT2", .artist: "TPE1", .album: "TALB", .albumArtist: "TPE2",
        .genre: "TCON", .track: "TRCK", .disc: "TPOS"
    ]
    private var version: UInt8
    private let originalTagSize: Int
    private var frames: [Frame]

    static func read(_ handle: FileHandle) throws -> Self {
        guard let header = try handle.read(upToCount: 10), header.count == 10 else { throw invalid }
        guard header.prefix(3) == Data("ID3".utf8) else {
            try handle.seek(toOffset: 0)
            return Self(version: 4, originalTagSize: 0, frames: [])
        }
        let version = header[3]
        guard version == 3 || version == 4, header[4] == 0, header[5] == 0,
              let length = integer(header[6..<10], synchsafe: true), length <= 16_000_000 else { throw invalid }
        let bytes = length > 0 ? (try handle.read(upToCount: length) ?? Data()) : Data()
        guard bytes.count == length else { throw invalid }
        var frames: [Frame] = []
        var index = 0
        while index < length {
            if bytes[index] == 0 {
                guard bytes[index...].allSatisfy({ $0 == 0 }) else { throw invalid }
                break
            }
            guard length - index >= 10, frames.count < 10_000,
                  let size = integer(bytes[(index + 4)..<(index + 8)], synchsafe: version == 4),
                  size > 0, size <= length - index - 10 else { throw invalid }
            let id = bytes[index..<(index + 4)]
            guard id.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { throw invalid }
            frames.append(Frame(id: String(decoding: id, as: UTF8.self),
                                flags: bytes.subdata(in: (index + 8)..<(index + 10)),
                                data: bytes.subdata(in: (index + 10)..<(index + 10 + size))))
            index += 10 + size
        }
        return Self(version: version, originalTagSize: length, frames: frames)
    }

    private static func integer(_ bytes: Data, synchsafe: Bool) -> Int? {
        guard !synchsafe || bytes.allSatisfy({ $0 < 128 }) else { return nil }
        return bytes.reduce(0) { ($0 << (synchsafe ? 7 : 8)) | Int($1) }
    }

    private static func bytes(_ value: Int, synchsafe: Bool) -> [UInt8] {
        let shift = synchsafe ? 7 : 8
        let mask = synchsafe ? 127 : 255
        return (0...3).reversed().map { UInt8((value >> ($0 * shift)) & mask) }
    }

    private func frameID(_ tag: MusicTag) -> String? {
        if tag == .year { return version == 3 ? "TYER" : "TDRC" }
        if tag == .recording { return "UFID" }
        if tag == .release { return "TXXX" }
        return Self.names[tag]
    }

    private func text(_ encoding: UInt8, bytes: Data) -> String? {
        let type: String.Encoding
        switch encoding {
        case 0: type = .isoLatin1
        case 1: type = .utf16
        case 2: type = .utf16BigEndian
        case 3: type = .utf8
        default: return nil
        }
        return String(data: bytes, encoding: type)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private func encoded(_ value: String) -> Data {
        version == 3 ? Data([1, 255, 254]) + (value.data(using: .utf16LittleEndian) ?? Data())
            : Data([3]) + Data(value.utf8)
    }

    private func userText(_ frame: Frame) -> (String, String)? {
        guard frame.flags.last == 0, let encoding = frame.data.first else { return nil }
        let data = Data(frame.data.dropFirst())
        let step = encoding == 1 || encoding == 2 ? 2 : 1
        for offset in stride(from: 0, to: data.count, by: step) where data.count - offset >= step {
            if data[offset..<(offset + step)].allSatisfy({ $0 == 0 }),
               let name = text(encoding, bytes: data.prefix(offset)),
               let value = text(encoding, bytes: data.dropFirst(offset + step)) {
                return (name, value)
            }
        }
        return nil
    }

    private let musicBrainzOwner = Data("http://musicbrainz.org\0".utf8)
    private let musicBrainzAlbum = "MusicBrainz Album Id"

    private func matches(_ frame: Frame, tag: MusicTag) -> Bool {
        guard frame.id == frameID(tag) else { return false }
        if tag == .recording { return frame.data.starts(with: musicBrainzOwner) }
        if tag == .release {
            return userText(frame)?.0.caseInsensitiveCompare(musicBrainzAlbum) == .orderedSame
        }
        return true
    }

    var values: [MusicTag: String] {
        MusicTag.allCases.reduce(into: [:]) { values, tag in
            guard let frame = frames.first(where: { matches($0, tag: tag) }), frame.flags.last == 0 else { return }
            if tag == .recording {
                values[tag] = String(data: frame.data.dropFirst(musicBrainzOwner.count), encoding: .ascii)
            } else if tag == .release {
                values[tag] = userText(frame)?.1
            } else if let encoding = frame.data.first {
                values[tag] = text(encoding, bytes: frame.data.dropFirst())
            }
        }
    }

    mutating func update(_ changes: [MusicTag: String], cover: MetadataCover?) throws {
        for tag in MusicTag.allCases {
            guard let value = changes[tag], let id = frameID(tag) else { continue }
            let candidates = frames.filter { $0.id == id }
            // A flagged custom-ID frame could hide the same identifier.
            guard candidates.allSatisfy({ $0.flags.last == 0 }) else { throw Self.invalid }
            let old = candidates.filter { matches($0, tag: tag) }
            guard old.allSatisfy({ $0.flags.first == 0 }) else { throw Self.invalid }
            let data: Data
            if tag == .recording {
                guard UUID(uuidString: value) != nil else { throw MetadataError("El ID de grabación debe ser un UUID válido.") }
                data = musicBrainzOwner + Data(value.utf8)
            } else if tag == .release {
                guard UUID(uuidString: value) != nil else { throw MetadataError("El ID de publicación debe ser un UUID válido.") }
                data = encoded(musicBrainzAlbum) + Data(repeating: 0, count: version == 3 ? 2 : 1) + encoded(value).dropFirst()
            } else if tag == .year && version == 3 {
                guard value.prefix(4).count == 4, value.prefix(4).utf8.allSatisfy({ (48...57).contains($0) }) else {
                    throw MetadataError("ID3v2.3 requiere un año de cuatro cifras.")
                }
                data = encoded(String(value.prefix(4)))
            } else {
                data = encoded(value)
            }
            frames = frames.filter { !matches($0, tag: tag) }
            frames.append(Frame(id: id, flags: Data([0, 0]), data: data))
        }
        if let cover = cover {
            let pictures = frames.filter { $0.id == "APIC" }
            guard pictures.allSatisfy({ $0.flags.last == 0 && pictureType($0) != nil }) else { throw Self.invalid }
            guard pictures.filter({ pictureType($0) == 3 }).allSatisfy({ $0.flags.first == 0 }) else { throw Self.invalid }
            let index = frames.firstIndex { $0.id == "APIC" } ?? frames.count
            frames = frames.filter { $0.id != "APIC" || pictureType($0) != 3 }
            let data = Data([0]) + Data(cover.mime.utf8) + Data([0, 3, 0]) + cover.data
            frames.insert(Frame(id: "APIC", flags: Data([0, 0]), data: data), at: index)
        }
    }

    private func pictureType(_ frame: Frame) -> UInt8? {
        guard let separator = frame.data.dropFirst().firstIndex(of: 0), separator + 1 < frame.data.count else {
            return nil
        }
        return frame.data[separator + 1]
    }

    func write(to handle: FileHandle) throws {
        var bytes = Data()
        for frame in frames {
            bytes.append(contentsOf: frame.id.utf8)
            bytes.append(contentsOf: Self.bytes(frame.data.count, synchsafe: version == 4))
            bytes.append(frame.flags)
            bytes.append(frame.data)
            guard bytes.count <= 16_000_000 else { throw Self.invalid }
        }
        if bytes.count < originalTagSize {
            bytes.append(Data(repeating: 0, count: originalTagSize - bytes.count))
        } else if bytes.count > originalTagSize,
                  frames.contains(where: { ["CHAP", "ASPI", "SEEK"].contains($0.id) }) {
            throw Self.invalid
        }
        let header = Data("ID3".utf8) + Data([version, 0, 0] + Self.bytes(bytes.count, synchsafe: true))
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: bytes)
    }

    func verifies(_ other: Self) -> Bool { version == other.version && frames == other.frames }
}
