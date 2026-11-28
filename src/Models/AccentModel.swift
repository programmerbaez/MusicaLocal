// Música Local — AccentModel
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Color de acento (sistema / carátula / personalizado)

enum AccentMode: String, CaseIterable, Identifiable {
    case system, artwork, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:  return "Sistema"
        case .artwork: return "Carátula"
        case .custom:  return "Color único"
        }
    }
}

/// Obtiene un color de la portada; también admite portadas monocromáticas.
enum Dominant {
    static func color(from image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = 48, h = 48
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }

        var weights = [Double](repeating: 0, count: 12)
        var sums = [[Double]](repeating: [0, 0, 0], count: 12)
        // Distribución de luminosidad para carátulas en blanco, negro o grises.
        var grayWeights = [Double](repeating: 0, count: 16)
        var graySum = [Double](repeating: 0, count: 16)
        var colorfulPixels = 0.0
        var colorWeight = 0.0

        for i in 0..<(w * h) {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            let d = mx - mn
            let s = mx == 0 ? 0 : d / mx
            let alpha = Double(pixels[i * 4 + 3]) / 255
            if alpha < 0.05 { continue }
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let grayBucket = min(15, Int(luminance * 16))
            grayWeights[grayBucket] += alpha
            graySum[grayBucket] += luminance * alpha
            // No ignorar colores vivos presentes en áreas relativamente pequeñas:
            // portadas como American Idiot combinan amplias regiones negras/blancas
            // con rojo intenso. Solo se consideran píxeles con cromaticidad real.
            if mx < 0.16 || s < 0.32 || d < 0.13 { continue }
            colorfulPixels += alpha

            var hue: Double
            if d == 0 { hue = 0 }
            else if mx == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { hue = (b - r) / d + 2 }
            else { hue = (r - g) / d + 4 }
            if hue < 0 { hue += 6 }

            let bucket = min(11, Int(hue / 6 * 12))
            let wgt = (s * s) * d * (0.40 + 0.60 * mx)
            weights[bucket] += wgt * alpha
            colorWeight += wgt * alpha
            sums[bucket][0] += r * wgt * alpha
            sums[bucket][1] += g * wgt * alpha
            sums[bucket][2] += b * wgt * alpha
        }

        // Una portada predominantemente negra o blanca aún debe conservar un
        // rojo, amarillo, etc., si ese color ocupa una región visible real.
        // El umbral del 1.8 % evita que unos pocos artefactos JPEG coloreen
        // una carátula genuinamente monocromática.
        let validPixels = grayWeights.reduce(0, +)
        if validPixels > 0, colorfulPixels / validPixels >= 0.018, colorWeight > 0,
           let best = weights.indices.max(by: { weights[$0] < weights[$1] }),
           weights[best] > 0 {
            let wt = weights[best]
            return NSColor(srgbRed: CGFloat(sums[best][0] / wt),
                           green: CGFloat(sums[best][1] / wt),
                           blue: CGFloat(sums[best][2] / wt),
                           alpha: 1)
        }

        // Portada monocromática: escoger una tonalidad realmente presente.
        // Se prefieren grises medios, para evitar elegir automáticamente el
        // blanco del fondo o un negro absoluto poco visible.
        guard validPixels > 0 else { return NSColor(calibratedWhite: 0.5, alpha: 1) }
        let grayIndex = grayWeights.indices.max { a, b in
            let centerA = (Double(a) + 0.5) / 16
            let centerB = (Double(b) + 0.5) / 16
            let scoreA = grayWeights[a] * (0.35 + 0.65 * (1 - abs(centerA - 0.5) * 1.6))
            let scoreB = grayWeights[b] * (0.35 + 0.65 * (1 - abs(centerB - 0.5) * 1.6))
            return scoreA < scoreB
        }!
        let gray = graySum[grayIndex] / max(grayWeights[grayIndex], 0.0001)
        return NSColor(calibratedWhite: CGFloat(gray), alpha: 1)
    }
}

/// Modelo del color de acento. Mantiene un color *mostrado* (`shown`) que se interpola
/// de forma continua hacia el color *objetivo* cada vez que cambia la canción, el modo,
/// el color personalizado o el esquema claro/oscuro.
final class AccentModel: ObservableObject {
    @Published var mode: AccentMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "accentMode")
            retarget()
            trackChanged(lastTrack)
        }
    }
    @Published var customHex: String {
        didSet {
            UserDefaults.standard.set(customHex, forKey: "accentHex")
            if mode == .custom { retarget(duration: 0.15) }
        }
    }
    @Published private(set) var shown: RGB

    private var target: RGB
    private var from: RGB
    private var startTime: TimeInterval = 0
    private var duration: TimeInterval = 0.6
    private var timer: Timer?

    private var dominant: NSColor?
    private var isDark = false
    private var lastTrack: Track?
    private var domCache: [String: NSColor] = [:]
    private var noDominant = Set<String>()
    private var pendingToken: ArtworkStore.Token = 0

    init() {
        let d = UserDefaults.standard
        let m = AccentMode(rawValue: d.string(forKey: "accentMode") ?? "") ?? .system
        let hex = d.string(forKey: "accentHex") ?? "#0A84FF"
        mode = m
        customHex = hex
        let t = AccentModel.compute(mode: m, hex: hex, dominant: nil, dark: false)
        shown = t
        target = t
        from = t
    }

    static func compute(mode: AccentMode, hex: String, dominant: NSColor?, dark: Bool) -> RGB {
        let sys = RGB(NSColor.controlAccentColor)
        switch mode {
        case .system:
            return sys
        case .custom:
            if let c = NSColor(hex: hex) { return RGB(c) }
            return sys
        case .artwork:
            guard let d = dominant else { return sys }
            return RGB(adjust(d, dark: dark))
        }
    }

    /// Ajusta brillo/saturación para que el color se lea bien en tema claro y oscuro.
    static func adjust(_ ns: NSColor, dark: Bool) -> NSColor {
        let c = ns.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.08 {
            // Mantener gris puro: no forzar saturación en portadas B/N.
            // Ajustar solo la luminosidad para que los controles sean visibles.
            let gray = dark ? min(max(b, 0.58), 0.85) : min(max(b, 0.27), 0.64)
            return NSColor(calibratedWhite: gray, alpha: 1)
        }
        s = min(max(s, 0.40), 0.95)
        b = dark ? min(max(b, 0.75), 1.0) : min(max(b, 0.40), 0.75)
        return NSColor(hue: h, saturation: s, brightness: b, alpha: 1)
    }

    func setScheme(dark: Bool) {
        guard dark != isDark else { return }
        isDark = dark
        retarget()
    }

    func invalidateArtwork(for track: Track) {
        domCache.removeValue(forKey: track.id)
        noDominant.remove(track.id)
        if lastTrack?.id == track.id { trackChanged(track) }
    }

    func trackChanged(_ track: Track?) {
        lastTrack = track
        guard mode == .artwork else { return }
        ArtworkStore.shared.cancel(pendingToken)
        guard let track = track else {
            dominant = nil
            retarget()
            return
        }
        // No conservar el acento de la canción anterior durante la carga.
        dominant = nil
        retarget()
        let id = track.id
        if let c = domCache[id] { dominant = c; retarget(); return }
        if noDominant.contains(id) { dominant = nil; retarget(); return }

        pendingToken = ArtworkStore.shared.request(url: track.url, large: true) { [weak self] img in
            guard let self = self, self.lastTrack?.id == id else { return }
            // Solo una carátula ausente permite recurrir al acento del sistema.
            let color = img.map { Dominant.color(from: $0) ?? NSColor(calibratedWhite: 0.5, alpha: 1) }
            if self.domCache.count > 500 { self.domCache.removeAll() }
            if let color = color { self.domCache[id] = color } else { self.noDominant.insert(id) }
            self.dominant = color
            self.retarget()
        }
    }

    // MARK: Interpolación

    private func retarget(duration d: TimeInterval = 0.6) {
        let t = AccentModel.compute(mode: mode, hex: customHex, dominant: dominant, dark: isDark)
        if t == target { return }
        target = t
        from = shown
        startTime = ProcessInfo.processInfo.systemUptime
        duration = d
        if timer == nil {
            let tm = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(tm, forMode: .common)     // sigue animando durante el scroll
            timer = tm
        }
    }

    private func tick() {
        let p = min(1, (ProcessInfo.processInfo.systemUptime - startTime) / max(duration, 0.01))
        let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2       // easeInOutCubic
        shown = RGB.mix(from, target, e)
        if p >= 1 {
            shown = target
            timer?.invalidate()
            timer = nil
        }
    }
}

