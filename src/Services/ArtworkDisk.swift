// Música Local — ArtworkDisk
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

/// Miniaturas JPEG en `Application Support/MusicaLocal/Artwork`. Permiten pintar la lista
/// sin volver a abrir cada archivo de audio (que es lo costoso) en las siguientes sesiones.
enum ArtworkDisk {
    static var directory: URL { CacheStore.directory.appendingPathComponent("Artwork", isDirectory: true) }

    static func key(for url: URL) -> String {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        var h: UInt64 = 0xcbf29ce484222325                    // FNV-1a 64 bits
        for b in "\(url.path)|\(Int(mtime))".utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }

    static func jpg(_ key: String) -> URL { directory.appendingPathComponent(key + ".jpg") }
    static func none(_ key: String) -> URL { directory.appendingPathComponent(key + ".none") }

    static func writeThumb(_ img: NSImage, key: String) {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: jpg(key), options: .atomic)
    }

    static func writeNone(key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: none(key), options: .atomic)
    }

    static func remove(_ key: String) {
        try? FileManager.default.removeItem(at: jpg(key))
        try? FileManager.default.removeItem(at: none(key))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    static var sizeBytes: Int64 {
        guard let en = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

