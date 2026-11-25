// Música Local — ArtworkStore
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Carátulas

/// Almacén de carátulas con:
///  · un único `AVURLAsset` por archivo (y una sola lectura sirve para miniatura y versión grande),
///  · caché en memoria (NSCache) y en disco (JPEG pequeños),
///  · cola LIFO con máximo 3 trabajos simultáneos (se atiende primero lo que está en pantalla),
///  · cancelación de lo que ya salió de pantalla y deduplicación de peticiones iguales.
final class ArtworkStore {
    static let shared = ArtworkStore()
    typealias Token = UInt64

    private struct Request {
        let id: Token
        let url: URL
        let large: Bool
        let completion: (NSImage?) -> Void
    }

    private let thumbs = NSCache<NSString, NSImage>()
    private let larges = NSCache<NSString, NSImage>()
    private var missing = Set<String>()
    private var pending: [String: [Request]] = [:]
    private var order: [String] = []
    private var inflight = Set<String>()
    private var active = 0
    private var nextToken: Token = 0
    private let maxActive = 3
    private let lock = NSLock()
    private let workQueue = DispatchQueue(label: "musicalocal.artwork",
                                          qos: .userInitiated,
                                          attributes: .concurrent)

    private init() {
        thumbs.countLimit = 1000
        larges.countLimit = 12
    }

    private static func key(_ path: String, _ large: Bool) -> String {
        path + (large ? "|L" : "|T")
    }

    func reset(clearDisk: Bool) {
        thumbs.removeAllObjects()
        larges.removeAllObjects()
        lock.lock(); missing.removeAll(); lock.unlock()
        ArtworkStore.clearFolderCache()
        if clearDisk { ArtworkDisk.clear() }
    }

    /// Pide una carátula. `completion` se llama en el hilo principal (de inmediato si ya está en memoria).
    @discardableResult
    func request(url: URL, large: Bool, completion: @escaping (NSImage?) -> Void) -> Token {
        let path = url.path
        let cache = large ? larges : thumbs
        if let hit = cache.object(forKey: path as NSString) {
            completion(hit)
            return 0
        }

        lock.lock()
        if missing.contains(path) {
            lock.unlock()
            completion(nil)
            return 0
        }
        nextToken += 1
        let tok = nextToken
        let k = ArtworkStore.key(path, large)
        pending[k, default: []].append(Request(id: tok, url: url, large: large, completion: completion))
        order.removeAll { $0 == k }
        order.append(k)
        lock.unlock()

        pump()
        return tok
    }

    func cancel(_ token: Token) {
        guard token != 0 else { return }
        lock.lock(); defer { lock.unlock() }
        for k in Array(pending.keys) {
            guard var reqs = pending[k] else { continue }
            let before = reqs.count
            reqs.removeAll { $0.id == token }
            if reqs.count != before {
                if reqs.isEmpty {
                    pending[k] = nil
                    order.removeAll { $0 == k }
                } else {
                    pending[k] = reqs
                }
                break
            }
        }
    }

    private func pump() {
        while true {
            lock.lock()
            guard active < maxActive else { lock.unlock(); return }

            var picked: (key: String, reqs: [Request])?
            while let k = order.popLast() {
                if inflight.contains(k) { continue }          // se atenderá al terminar el trabajo en curso
                if let reqs = pending.removeValue(forKey: k), !reqs.isEmpty {
                    picked = (k, reqs)
                    break
                }
            }
            guard let job = picked else { lock.unlock(); return }
            inflight.insert(job.key)
            active += 1
            lock.unlock()

            workQueue.async { self.process(key: job.key, requests: job.reqs) }
        }
    }

    private func process(key: String, requests: [Request]) {
        let first = requests[0]
        let image = produce(url: first.url, large: first.large)
        finish(key: key, path: first.url.path, large: first.large, image: image, requests: requests)
    }

    private func finish(key: String, path: String, large: Bool, image: NSImage?, requests: [Request]) {
        if let image = image {
            (large ? larges : thumbs).setObject(image, forKey: path as NSString)
        }
        lock.lock()
        if image == nil { missing.insert(path) }
        inflight.remove(key)
        active -= 1
        let late = pending.removeValue(forKey: key) ?? []
        order.removeAll { $0 == key }
        lock.unlock()

        let all = requests + late
        DispatchQueue.main.async {
            for r in all { r.completion(image) }
        }
        pump()
    }

    // MARK: Producción de imágenes

    private func produce(url: URL, large: Bool) -> NSImage? {
        let path = url.path
        let nsPath = path as NSString
        let diskOn = UserDefaults.standard.bool(forKey: "cacheEnabled")
        let dkey = diskOn ? ArtworkDisk.key(for: url) : ""

        if !large {
            // 1) A partir de la versión grande ya decodificada
            if let big = larges.object(forKey: nsPath), let t = ArtworkStore.resize(big, maxPixel: 120) {
                if diskOn { ArtworkDisk.writeThumb(t, key: dkey) }
                return t
            }
            // 2) Desde la caché de disco (sin abrir el audio)
            if diskOn {
                if FileManager.default.fileExists(atPath: ArtworkDisk.none(dkey).path) { return nil }
                if let data = try? Data(contentsOf: ArtworkDisk.jpg(dkey)), let img = NSImage(data: data) {
                    return img
                }
            }
        }

        // 3) Lectura real del archivo (un único AVURLAsset)
        guard let data = ArtworkStore.rawArtwork(for: url) else {
            if diskOn { ArtworkDisk.writeNone(key: dkey) }
            return nil
        }

        if large {
            guard let big = ArtworkStore.decode(data, maxPixel: 700) else { return nil }
            if thumbs.object(forKey: nsPath) == nil, let t = ArtworkStore.resize(big, maxPixel: 120) {
                thumbs.setObject(t, forKey: nsPath)
                if diskOn { ArtworkDisk.writeThumb(t, key: dkey) }
            }
            return big
        } else {
            guard let t = ArtworkStore.decode(data, maxPixel: 120) else { return nil }
            if diskOn { ArtworkDisk.writeThumb(t, key: dkey) }
            return t
        }
    }

    // 1) Etiquetas incrustadas (ID3, iTunes)  2) FLAC  3) imagen en la carpeta
    static func rawArtwork(for url: URL) -> Data? {
        if url.pathExtension.lowercased() == "flac", let d = flacPicture(url) { return d }

        let asset = AVURLAsset(url: url)
        if let d = artData(in: asset.commonMetadata) { return d }
        if let d = artData(in: asset.metadata) { return d }
        return folderImage(near: url)
    }

    private static func artData(in items: [AVMetadataItem]) -> Data? {
        for item in items {
            let isArt = item.commonKey == .commonKeyArtwork
                || item.identifier == .id3MetadataAttachedPicture
                || item.identifier == .iTunesMetadataCoverArt
            if isArt {
                if let d = item.dataValue, !d.isEmpty { return d }
                if let d = item.value as? Data, !d.isEmpty { return d }
            }
        }
        return nil
    }

    static func decode(_ data: Data, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func resize(_ img: NSImage, maxPixel: Int) -> NSImage? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = Double(maxPixel) / Double(max(cg.width, cg.height))
        if scale >= 1 { return img }
        let w = max(1, Int(Double(cg.width) * scale))
        let h = max(1, Int(Double(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }

    // MARK: Imagen de carpeta (cover.jpg, folder.png…) con caché por directorio

    private static let folderData = NSCache<NSString, NSData>()
    private static var foldersWithoutArt = Set<String>()
    private static let folderLock = NSLock()

    static func clearFolderCache() {
        folderData.removeAllObjects()
        folderLock.lock(); foldersWithoutArt.removeAll(); folderLock.unlock()
    }

    private static func folderImage(near url: URL) -> Data? {
        let dir = url.deletingLastPathComponent()
        let dkey = dir.path as NSString

        if let cached = folderData.object(forKey: dkey) { return cached as Data }
        folderLock.lock()
        let known = foldersWithoutArt.contains(dir.path)
        folderLock.unlock()
        if known { return nil }

        var result: Data?
        if let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let exts: Set<String> = ["jpg", "jpeg", "png"]
            let images = files.filter { exts.contains($0.pathExtension.lowercased()) }
            let names = ["cover", "folder", "front", "album", "albumart", "artwork", "thumb"]
            for n in names {
                if let f = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == n }) {
                    result = try? Data(contentsOf: f)
                    break
                }
            }
            if result == nil, images.count == 1 { result = try? Data(contentsOf: images[0]) }
        }

        if let r = result {
            folderData.setObject(r as NSData, forKey: dkey)
        } else {
            folderLock.lock(); foldersWithoutArt.insert(dir.path); folderLock.unlock()
        }
        return result
    }

    // MARK: Lector mínimo del bloque PICTURE de FLAC

    private static func flacPicture(_ url: URL) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let magic = try? fh.read(upToCount: 4), magic == Data("fLaC".utf8) else { return nil }

        while true {
            guard let hdrData = try? fh.read(upToCount: 4), hdrData.count == 4 else { return nil }
            let hdr = [UInt8](hdrData)
            let isLast = (hdr[0] & 0x80) != 0
            let type = hdr[0] & 0x7F
            let len = Int(hdr[1]) << 16 | Int(hdr[2]) << 8 | Int(hdr[3])

            if type == 6 {
                guard len > 32, len < 30_000_000,
                      let block = try? fh.read(upToCount: len), block.count == len else { return nil }
                return parseFlacPicture([UInt8](block))
            } else {
                guard let pos = try? fh.offset() else { return nil }
                do { try fh.seek(toOffset: pos + UInt64(len)) } catch { return nil }
            }
            if isLast { return nil }
        }
    }

    private static func parseFlacPicture(_ b: [UInt8]) -> Data? {
        func be32(_ o: Int) -> Int? {
            guard o + 4 <= b.count else { return nil }
            return Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
        }
        var o = 4                                   // tipo de imagen
        guard let mimeLen = be32(o) else { return nil }
        o += 4 + mimeLen
        guard let descLen = be32(o) else { return nil }
        o += 4 + descLen
        o += 16                                     // ancho, alto, profundidad, colores
        guard let dataLen = be32(o) else { return nil }
        o += 4
        guard dataLen > 0, o + dataLen <= b.count else { return nil }
        return Data(b[o..<(o + dataLen)])
    }
}

