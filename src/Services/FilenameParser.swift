// Música Local — FilenameParser
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

/// Deduce "Artista - Título" a partir del nombre del archivo cuando faltan las etiquetas.
enum FilenameParser {
    static func parse(_ base: String) -> (artist: String?, title: String) {
        var s = base.trimmingCharacters(in: .whitespaces)

        // Quita numeración de pista: "01. ", "01 - ", "1_", "03) ", o "01 " con cero a la izquierda
        if let r = s.range(of: #"^\d{1,3}\s*[.\-_)]\s*"#, options: .regularExpression) {
            let rest = String(s[r.upperBound...])
            if !rest.isEmpty { s = rest }
        } else if let r = s.range(of: #"^0\d{1,2}\s+"#, options: .regularExpression) {
            let rest = String(s[r.upperBound...])
            if !rest.isEmpty { s = rest }
        }

        for sep in [" - ", " – ", " — "] {
            if let r = s.range(of: sep) {
                let a = s[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let t = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !a.isEmpty, !t.isEmpty, a.count <= 80 { return (a, t) }
            }
        }
        return (nil, s)
    }
}

