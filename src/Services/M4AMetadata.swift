import Foundation

/// Edits the iTunes metadata of a self-contained, unfragmented M4A. Media offsets
/// stay fixed even if the original movie atom precedes the media data.
struct M4AMetadata {
    private struct Atom: Equatable {
        let type: String
        let data: Data

        var bytes: Data { M4AMetadata.integer(data.count + 8) + M4AMetadata.code(type) + data }
        static func pack(_ atoms: [Self]) -> Data {
            atoms.reduce(into: Data()) { $0.append($1.bytes) }
        }

        static func parse(_ input: Data) throws -> [Self] {
            let bytes = Data(input)
            var atoms: [Self] = []
            var position = 0
            while position < bytes.count {
                guard bytes.count - position >= 8, atoms.count < 10_000 else { throw invalid }
                let size = number(bytes[position..<(position + 4)])
                let type = name(bytes[(position + 4)..<(position + 8)])
                guard size >= 8, size <= bytes.count - position else { throw invalid }
                atoms.append(Self(type: type, data: bytes.subdata(in: (position + 8)..<(position + size))))
                position += size
            }
            return atoms
        }
    }

    static let invalid = MetadataError("La estructura de este M4A no permite editar sus etiquetas con seguridad.")
    private static let textNames: [MusicTag: String] = [
        .title: "©nam", .artist: "©ART", .album: "©alb", .albumArtist: "aART", .year: "©day", .genre: "©gen"
    ]
    private static let customNames: [MusicTag: String] = [
        .recording: "MusicBrainz Track Id", .release: "MusicBrainz Album Id"
    ]
    private static let namespace = Data("com.apple.iTunes".utf8)
    private var movie: [Atom]
    private var userData: [Atom]
    private var meta: [Atom]
    private var items: [Atom]
    let movieOffset: UInt64
    let movieSize: UInt64
    let fileSize: UInt64
    var movieEnd: UInt64 { movieOffset + movieSize }

    static func read(_ handle: FileHandle) throws -> Self {
        let fileSize = try handle.seekToEnd()
        var position: UInt64 = 0
        var movie: (UInt64, UInt64, Data)?
        var hasMedia = false
        var count = 0
        while position < fileSize {
            count += 1
            guard count <= 1024, fileSize - position >= 8 else { throw invalid }
            try handle.seek(toOffset: position)
            guard let header = try handle.read(upToCount: 8), header.count == 8 else { throw invalid }
            let type = name(header.suffix(4))
            var size = UInt64(number(header.prefix(4)))
            var headerSize: UInt64 = 8
            if size == 1 {
                guard let extended = try handle.read(upToCount: 8), extended.count == 8 else { throw invalid }
                size = extended.reduce(0) { ($0 << 8) | UInt64($1) }
                headerSize = 16
            }
            guard ["ftyp", "free", "skip", "wide", "mdat", "moov"].contains(type),
                  size >= headerSize, size <= fileSize - position else { throw invalid }
            if position == 0, type != "ftyp" { throw invalid }
            if type == "moov" {
                guard movie == nil, size <= 32 * 1024 * 1024, size > headerSize,
                      let bytes = try handle.read(upToCount: Int(size - headerSize)),
                      UInt64(bytes.count) == size - headerSize else { throw invalid }
                movie = (position, size, bytes)
            } else if type == "mdat" {
                guard size > headerSize else { throw invalid }
                hasMedia = true
            }
            position += size
        }
        guard let (offset, size, bytes) = movie, hasMedia else { throw invalid }
        let children = try Atom.parse(bytes)
        guard children.contains(where: { $0.type == "trak" }),
              !children.contains(where: { ["mvex", "cmov", "rmra", "meta", "iloc"].contains($0.type) }) else { throw invalid }
        let userData = try child("udta", of: children).map { try Atom.parse($0.data) } ?? []
        let metadata = try child("meta", of: userData)
        var meta: [Atom]
        if let metadata = metadata {
            guard metadata.data.prefix(4) == Data(repeating: 0, count: 4) else { throw invalid }
            meta = try Atom.parse(metadata.data.dropFirst(4))
            guard let handler = try child("hdlr", of: meta), handler.data.count >= 12,
                  handler.data[8..<12] == code("mdir"),
                  !meta.contains(where: { ["keys", "iloc"].contains($0.type) }) else { throw invalid }
        } else {
            let handler = Data(repeating: 0, count: 8) + code("mdir") + code("appl") +
                Data(repeating: 0, count: 9)
            meta = [Atom(type: "hdlr", data: handler)]
        }
        let items = try child("ilst", of: meta).map { try Atom.parse($0.data) } ?? []
        return Self(movie: children, userData: userData, meta: meta, items: items,
                    movieOffset: offset, movieSize: size, fileSize: fileSize)
    }

    private static func child(_ type: String, of atoms: [Atom]) throws -> Atom? {
        let matches = atoms.filter { $0.type == type }
        guard matches.count <= 1 else { throw invalid }
        return matches.first
    }

    private static func replace(_ atom: Atom, in atoms: inout [Atom]) {
        if let index = atoms.firstIndex(where: { $0.type == atom.type }) { atoms[index] = atom }
        else { atoms.append(atom) }
    }

    private static func number(_ data: Data) -> Int { data.reduce(0) { ($0 << 8) | Int($1) } }
    private static func integer(_ n: Int) -> Data {
        Data([24, 16, 8, 0].map { UInt8(truncatingIfNeeded: n >> $0) })
    }
    private static func code(_ type: String) -> Data { Data(type.unicodeScalars.map { UInt8($0.value) }) }
    private static func name(_ data: Data) -> String {
        String(String.UnicodeScalarView(data.map { UnicodeScalar($0) }))
    }

    private func matches(_ item: Atom, tag: MusicTag) throws -> Bool {
        if let name = Self.textNames[tag] { return item.type == name }
        if tag == .track { return item.type == "trkn" }
        if tag == .disc { return item.type == "disk" }
        guard item.type == "----", let name = Self.customNames[tag] else { return false }
        let children = try Atom.parse(item.data)
        let domain = try Self.child("mean", of: children)
        let key = try Self.child("name", of: children)
        return domain?.data.dropFirst(4) == Self.namespace &&
            String(data: Data(key?.data.dropFirst(4) ?? Data()), encoding: .utf8)?
                .caseInsensitiveCompare(name) == .orderedSame
    }

    private func payload(_ item: Atom) throws -> (Int, Data) {
        let children = try Atom.parse(item.data)
        guard let data = try Self.child("data", of: children), data.data.count >= 8 else { throw Self.invalid }
        return (Self.number(data.data.prefix(4)), Data(data.data.dropFirst(8)))
    }

    var values: [MusicTag: String] {
        MusicTag.allCases.reduce(into: [:]) { values, tag in
            guard let item = items.first(where: { (try? matches($0, tag: tag)) == true }),
                  let (type, value) = try? payload(item) else { return }
            if tag == .track || tag == .disc {
                if type == 0, value.count >= 6 {
                    let number = Self.number(value[2..<4])
                    let total = Self.number(value[4..<6])
                    if number > 0 { values[tag] = total > 0 ? "\(number)/\(total)" : String(number) }
                }
            } else if type == 1 {
                values[tag] = String(data: value, encoding: .utf8)
            } else if type == 2 {
                values[tag] = String(data: value, encoding: .utf16BigEndian)
            }
        }
    }

    mutating func update(_ changes: [MusicTag: String], cover: MetadataCover?) throws {
        for tag in MusicTag.allCases {
            guard let value = changes[tag] else { continue }
            let existing = try items.filter { try matches($0, tag: tag) }
            let item: Atom
            if tag == .track || tag == .disc {
                let parts = value.split(separator: "/", omittingEmptySubsequences: false)
                let oldTotal = values[tag]?.split(separator: "/").dropFirst().first.flatMap { UInt16($0) } ?? 0
                guard let first = parts.first, let number = UInt16(first), number > 0,
                      parts.count <= 2, let total = parts.count == 2 ? UInt16(parts[1]) : oldTotal else {
                    throw MetadataError("Los números de disco y pista requieren un entero positivo o número/total en M4A.")
                }
                var payload = Data([0, 0]) + Self.integer(Int(number)).suffix(2) + Self.integer(Int(total)).suffix(2)
                if tag == .track { payload.append(contentsOf: [0, 0]) }
                item = Atom(type: tag == .track ? "trkn" : "disk", data: Self.dataAtom(type: 0, payload: payload).bytes)
            } else {
                let data = Self.dataAtom(type: 1, payload: Data(value.utf8))
                if let custom = Self.customNames[tag] {
                    guard UUID(uuidString: value) != nil else { throw MetadataError("Los identificadores de MusicBrainz deben ser UUID válidos.") }
                    let zero = Self.integer(0)
                    let mean = Atom(type: "mean", data: zero + Self.namespace)
                    let name = Atom(type: "name", data: zero + Data(custom.utf8))
                    item = Atom(type: "----", data: Atom.pack([mean, name, data]))
                } else if let name = Self.textNames[tag] {
                    item = Atom(type: name, data: data.bytes)
                } else { continue }
            }
            // Refuse subtags we would otherwise discard from a field being replaced.
            for field in existing {
                let allowed = field.type == "----" ? ["mean", "name", "data"] : ["data"]
                guard try Atom.parse(field.data).allSatisfy({ allowed.contains($0.type) }) else { throw Self.invalid }
            }
            items = try items.filter { try !matches($0, tag: tag) }
            items.append(item)
        }
        if let cover = cover {
            let old = items.filter { $0.type == "covr" }
            let first = Self.dataAtom(type: cover.mime == "image/png" ? 14 : 13, payload: cover.data)
            // MP4 gives cover data no front/back role. Replace the first image and keep the rest.
            let pictures = try old.flatMap { try Atom.parse($0.data) }
            guard pictures.allSatisfy({ $0.type == "data" }) else { throw Self.invalid }
            items.removeAll { $0.type == "covr" }
            items.append(Atom(type: "covr", data: Atom.pack([first] + Array(pictures.dropFirst()))))
        }
        Self.replace(Atom(type: "ilst", data: Atom.pack(items)), in: &meta)
        Self.replace(Atom(type: "meta", data: Self.integer(0) + Atom.pack(meta)), in: &userData)
        Self.replace(Atom(type: "udta", data: Atom.pack(userData)), in: &movie)
    }

    private static func dataAtom(type: Int, payload: Data) -> Atom {
        Atom(type: "data", data: integer(type) + integer(0) + payload)
    }

    func write(to handle: FileHandle) throws {
        let data = Atom.pack(movie)
        guard data.count < 32 * 1024 * 1024 - 8 else { throw Self.invalid }
        try handle.write(contentsOf: Atom(type: "moov", data: data).bytes)
    }

    func reserveOriginalMovie(in handle: FileHandle) throws {
        try handle.write(contentsOf: Self.integer(Int(movieSize)) + Self.code("free"))
        try handle.seek(toOffset: movieEnd)
    }

    func verifies(_ other: Self) -> Bool { movie == other.movie && items == other.items }
}
