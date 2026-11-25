// Música Local — LibraryCache
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Caché de biblioteca en disco

struct CachedTrack: Codable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var mtime: Double
}

struct LibraryCache: Codable {
    static let currentVersion = 2

    var folderPath: String
    var entries: [String: CachedTrack]
    var version: Int?
}

enum CacheStore {
    static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicaLocal", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("library.json") }

    static func load() -> LibraryCache? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LibraryCache.self, from: data)
    }

    static func save(_ cache: LibraryCache) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var sizeBytes: Int64 {
        let v = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }
}

