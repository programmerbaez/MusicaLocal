// Música Local — fondo del instalador generado con AppKit.
// El diseño se dibuja a partir de rutas y texto, sin imágenes externas.
// Uso: ./DMGBackground <ancho> <alto> <salida.png> [escala]
// <ancho> y <alto> están en PUNTOS (lo que Finder muestra). Con escala 2 el PNG
// tiene el doble de píxeles y metadatos de 144 dpi, para pantallas Retina.
import AppKit
import Foundation

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func textCentered(_ string: String, centerX: CGFloat, baselineY: CGFloat,
                  size: CGFloat, serif: Bool = false, weight: NSFont.Weight = .regular,
                  foreground: NSColor, italic: Bool = false) {
    let font: NSFont
    if serif {
        let familyName = italic ? "Georgia-Italic" : (weight == .semibold ? "Georgia-Bold" : "Georgia")
        font = NSFont(name: familyName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    } else {
        font = NSFont.systemFont(ofSize: size, weight: weight)
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph
    ]
    let width = max(1, canvasWidth - 40)
    NSAttributedString(string: string, attributes: attributes)
        .draw(in: NSRect(x: centerX - width/2, y: baselineY, width: width, height: size * 1.6))
}

var canvasWidth: CGFloat = 760

// Cada palma se construye con una espina y hojas Bézier independientes.
func palm(origin: NSPoint, angle: CGFloat, length: CGFloat, flip: CGFloat, opacity: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let transformObj = NSAffineTransform()
    transformObj.translateX(by: origin.x, yBy: origin.y)
    transformObj.rotate(byRadians: angle)
    transformObj.scaleX(by: length, yBy: length * flip)
    transformObj.concat()

    let stem = NSBezierPath()
    stem.lineWidth = 0.009
    stem.move(to: NSPoint(x: 0, y: 0))
    stem.curve(to: NSPoint(x: 1, y: 0.05),
               controlPoint1: NSPoint(x: 0.38, y: 0.06),
               controlPoint2: NSPoint(x: 0.69, y: 0.15))
    color(58, 91, 37, opacity).setStroke()
    stem.stroke()

    for i in 0..<15 {
        let v = CGFloat(i) / 15
        let x = 0.09 + v * 0.80
        let arch: CGFloat = 0.04 + 0.10 * sin(v * .pi)
        let halfWidth = (0.20 * (1 - pow(v, 1.3)) + 0.035)
        for sign in [-1.0, 1.0] as [CGFloat] {
            let blade = NSBezierPath()
            let y = arch * sign
            blade.move(to: NSPoint(x: x, y: y))
            let tip = NSPoint(x: x + halfWidth * 0.48, y: sign * (arch + halfWidth * 1.52))
            blade.curve(to: tip,
                controlPoint1: NSPoint(x: x + halfWidth * 0.07, y: y + sign * halfWidth * 0.52),
                controlPoint2: NSPoint(x: x + halfWidth * 0.38, y: sign * (arch + halfWidth * 1.24)))
            blade.curve(to: NSPoint(x: x + 0.045, y: y),
                controlPoint1: NSPoint(x: x + halfWidth * 0.31, y: sign * (arch + halfWidth * 1.15)),
                controlPoint2: NSPoint(x: x + 0.06, y: y + sign * halfWidth * 0.22))
            blade.close()
            let shade = CGFloat(i % 4) * 6
            color(36 + shade, 77 + shade, 30 + shade/2, opacity).setFill()
            blade.fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

func draw(width w: CGFloat, height h: CGFloat) {
    canvasWidth = w
    let rect = NSRect(x: 0, y: 0, width: w, height: h)
    let base = NSBezierPath(rect: rect)
    (NSGradient(starting: color(250, 247, 239), ending: color(238, 232, 218)))?
        .draw(in: base, angle: 90)

    // Sombra suavizada y borde decorativo sutil.
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 12, yRadius: 12)
    border.lineWidth = 0.7
    color(180, 174, 150, 0.20).setStroke()
    border.stroke()

    let s = min(w, h)
    palm(origin: NSPoint(x: -w*0.04, y: h*1.06), angle: -0.48, length: s*0.87, flip: -1, opacity: 0.90)
    palm(origin: NSPoint(x: w*1.04, y: h*1.06), angle: -2.66, length: s*0.85, flip: 1, opacity: 0.86)
    palm(origin: NSPoint(x: -w*0.06, y: -h*0.06), angle: 0.47, length: s*0.70, flip: 1, opacity: 0.72)
    palm(origin: NSPoint(x: w*1.05, y: -h*0.06), angle: 2.72, length: s*0.70, flip: -1, opacity: 0.72)

    // Todo el texto se escala en función de las dimensiones del DMG.
    let titleSize = min(47, max(28, w * 0.060))
    textCentered("Música Local", centerX: w/2, baselineY: h*0.765,
                 size: titleSize, serif: true, weight: .semibold, foreground: color(39, 59, 29))
    textCentered("Tu música. Tu espacio.", centerX: w/2, baselineY: h*0.697,
                 size: min(20, w*0.027), serif: true, foreground: color(94, 112, 66), italic: true)

    // Divisor central ligero, lejos de los iconos de Finder.
    let line = NSBezierPath()
    line.move(to: NSPoint(x: w*0.39, y: h*0.664))
    line.line(to: NSPoint(x: w*0.61, y: h*0.664))
    line.lineWidth = 1
    color(125, 139, 96, 0.36).setStroke()
    line.stroke()

    textCentered("Versión 1.0  ·  macOS", centerX: w/2, baselineY: h*0.085,
                 size: min(14, w*0.019), foreground: color(99, 112, 79))
}

let args = CommandLine.arguments
if args.count != 4 && args.count != 5 {
    fputs("Uso: DMGBackground <ancho> <alto> <salida.png> [escala 1-4]\n", stderr)
    exit(2)
}
guard let wi = Int(args[1]), let hi = Int(args[2]),
      (600...1800).contains(wi), (360...1000).contains(hi) else {
    fputs("Dimensiones inválidas; utiliza ancho 600–1800 y alto 360–1000.\n", stderr)
    exit(2)
}
let scale = args.count == 5 ? (Int(args[4]) ?? 0) : 1
guard (1...4).contains(scale) else {
    fputs("Escala inválida; utiliza un entero de 1 a 4.\n", stderr)
    exit(2)
}
let w = CGFloat(wi), h = CGFloat(hi)
let pxW = wi * scale, pxH = hi * scale

// El bitmap tiene `scale` veces más píxeles que puntos.
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW,
                                    pixelsHigh: pxH, bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("No se pudo crear el contexto gráfico.\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true
// Se dibuja en puntos; el contexto escala a píxeles reales.
context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
draw(width: w, height: h)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

// Etiqueta sRGB y tamaño en puntos => 72 dpi (1x) o 144 dpi (2x) en el PNG.
let output = bitmap.retagging(with: .sRGB) ?? bitmap
output.size = NSSize(width: w, height: h)
guard let bytes = output.representation(using: .png, properties: [:]) else {
    fputs("No se pudo codificar PNG.\n", stderr)
    exit(1)
}
do {
    try bytes.write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    print("Fondo generado con Swift: \(wi) × \(hi) pt @\(scale)x (\(pxW) × \(pxH) px) -> \(args[3])")
} catch {
    fputs("Error al guardar el fondo: \(error)\n", stderr)
    exit(1)
}
