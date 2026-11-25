// Música Local — Colors
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Utilidades de color

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Color sRGB simple, interpolable en luz lineal (sin cortes ni "barro" a mitad de camino).
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)
        r = Double(c.redComponent)
        g = Double(c.greenComponent)
        b = Double(c.blueComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    static func mix(_ from: RGB, _ to: RGB, _ t: Double) -> RGB {
        func lin(_ v: Double) -> Double { pow(max(v, 0), 2.2) }
        func gam(_ v: Double) -> Double { pow(max(v, 0), 1 / 2.2) }
        func ch(_ x: Double, _ y: Double) -> Double { gam(lin(x) + (lin(y) - lin(x)) * t) }
        return RGB(r: ch(from.r, to.r), g: ch(from.g, to.g), b: ch(from.b, to.b))
    }
}

