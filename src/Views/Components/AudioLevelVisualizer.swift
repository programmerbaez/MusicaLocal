// Música Local — visualizaciones ligeras del nivel de audio.
// Una sola lectura de PlaybackClock se reutiliza en todas las vistas.
// Importante: no hay FFT; la distribución de columnas es ilustrativa, no bandas reales.
import SwiftUI

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case off, bars, curve, segmented, dots, mountain

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Desactivado"
        case .bars: return "Barras verticales"
        case .curve: return "Línea (curva)"
        case .segmented: return "Ecualizador segmentado"
        case .dots: return "Puntos"
        case .mountain: return "Montaña"
        }
    }
    var description: String {
        switch self {
        case .off: return "Oculta el visualizador y evita dibujarlo."
        case .bars: return "Columnas verticales continuas (diseño original)."
        case .curve: return "Trazo suave y discreto sobre el fondo translúcido."
        case .segmented: return "Indicadores apilados como un medidor LED."
        case .dots: return "Columnas de pequeños puntos luminosos."
        case .mountain: return "Crestas superpuestas, similares a un paisaje."
        }
    }
}

struct AudioLevelVisualizer: View {
    @ObservedObject var clock: PlaybackClock
    let tint: Color
    @AppStorage("visualizerStyle") private var styleRaw = VisualizerStyle.bars.rawValue

    private let columns = 18
    private var style: VisualizerStyle { VisualizerStyle(rawValue: styleRaw) ?? .bars }

    var body: some View {
        GeometryReader { geo in
            Group {
                switch style {
                case .off:
                    Color.clear
                case .bars:
                    columnsView(size: geo.size, segmented: false, dotted: false)
                case .segmented:
                    columnsView(size: geo.size, segmented: true, dotted: false)
                case .dots:
                    columnsView(size: geo.size, segmented: false, dotted: true)
                case .curve:
                    curveView(size: geo.size)
                case .mountain:
                    mountainView(size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.16), value: clock.audioLevel)
        .accessibilityLabel("Visualizador: \(style.label)")
    }

    // La amplitud de la señal regula todas las figuras. La modulación por columna
    // solo crea un perfil gráfico: no atribuir frecuencias inexistentes al audio.
    private func level(_ index: Int, shift: Double = 0) -> Double {
        let x = Double(index)
        let phase = clock.progress * 3.5
        let contour = 0.42 + 0.58 * abs(sin(x * 0.68 + phase + shift))
        return max(0, min(1, clock.audioLevel * contour))
    }

    private func columnsView(size: CGSize, segmented: Bool, dotted: Bool) -> some View {
        let spacing: CGFloat = dotted ? 4 : 3
        let width = max(2, (size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let cell: CGFloat = dotted ? 3.0 : 3.0
        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { index in
                if segmented || dotted {
                    let count = max(1, Int((size.height + 1) / (cell + 2)))
                    let active = Int((level(index) * Double(count)).rounded())
                    VStack(spacing: 2) {
                        ForEach((0..<count).reversed(), id: \.self) { segment in
                            RoundedRectangle(cornerRadius: dotted ? cell / 2 : 1)
                                .fill(tint.opacity(segment < active ? 0.95 : 0.12))
                                .frame(width: dotted ? min(cell, width) : width, height: cell)
                        }
                    }
                    .frame(width: width, height: size.height, alignment: .bottom)
                } else {
                    Capsule()
                        .fill(tint.opacity(0.55 + 0.45 * Double(index % 4 + 1) / 4))
                        .frame(width: width, height: max(2, size.height * CGFloat(level(index))))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    private func curveView(size: CGSize) -> some View {
        Path { path in
            guard size.width > 0, size.height > 0 else { return }
            let step = size.width / CGFloat(columns - 1)
            for i in 0..<columns {
                let point = CGPoint(x: CGFloat(i) * step,
                                    y: size.height - 2 - CGFloat(level(i)) * max(0, size.height - 4))
                if i == 0 {
                    path.move(to: point)
                } else {
                    // Curva cuadrática para suavizar la transición entre muestras.
                    let previous = CGPoint(x: CGFloat(i - 1) * step,
                                           y: size.height - 2 - CGFloat(level(i - 1)) * max(0, size.height - 4))
                    let mid = CGPoint(x: (previous.x + point.x) / 2,
                                      y: (previous.y + point.y) / 2)
                    path.addQuadCurve(to: mid, control: previous)
                    if i == columns - 1 { path.addLine(to: point) }
                }
            }
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func mountainView(size: CGSize) -> some View {
        ZStack {
            mountainPath(size: size, shift: 1.5, scale: 0.55)
                .fill(tint.opacity(0.22))
            mountainPath(size: size, shift: 0, scale: 1)
                .fill(tint.opacity(0.62))
            mountainPath(size: size, shift: 0, scale: 1)
                .stroke(tint.opacity(0.85), lineWidth: 1)
        }
    }

    private func mountainPath(size: CGSize, shift: Double, scale: Double) -> Path {
        Path { path in
            guard size.width > 0, size.height > 0 else { return }
            path.move(to: CGPoint(x: 0, y: size.height))
            for i in 0..<columns {
                let x = CGFloat(i) * size.width / CGFloat(columns - 1)
                let y = size.height - CGFloat(level(i, shift: shift) * scale) * size.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }
}
