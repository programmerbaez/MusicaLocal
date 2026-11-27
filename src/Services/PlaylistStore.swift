import Foundation

struct Playlist: Codable, Identifiable {
    let name: String
    var trackPaths: [String]

    var id: String { name }
}

enum PlaylistStore {
    enum StoreError: LocalizedError {
        case invalidName, duplicateName

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "Escribe un nombre de hasta 200 bytes que no comience con un punto ni contenga /, : o caracteres de control."
            case .duplicateName:
                return "Ya existe una lista de reproducción con ese nombre."
            }
        }
    }

    static var directory: URL {
        CacheStore.directory.appendingPathComponent("Playlist", isDirectory: true)
    }

    static func load(from directory: URL = directory) -> [Playlist] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []
        return files.compactMap { file -> Playlist? in
            guard file.pathExtension == "js",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: file),
                  let playlist = try? JSONDecoder().decode(Playlist.self, from: data),
                  playlist.name == file.deletingPathExtension().lastPathComponent,
                  (try? validatedName(playlist.name)) == playlist.name else { return nil }
            return playlist
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func create(named input: String, in directory: URL = directory) throws -> Playlist {
        let name = try validatedName(input)
        let file = fileURL(for: name, in: directory)
        if FileManager.default.fileExists(atPath: file.path) {
            throw StoreError.duplicateName
        }
        let playlist = Playlist(name: name, trackPaths: [])
        try save(playlist, in: directory)
        return playlist
    }

    static func save(_ playlist: Playlist, in directory: URL = directory) throws {
        let name = try validatedName(playlist.name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(playlist)
        try data.write(to: fileURL(for: name, in: directory), options: .atomic)
    }

    private static func validatedName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), name.utf8.count <= 200,
              name.rangeOfCharacter(from: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))) == nil
        else { throw StoreError.invalidName }
        return name
    }

    private static func fileURL(for name: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(name).js", isDirectory: false)
    }
}
