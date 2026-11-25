import SwiftUI
import AppKit

/// Ventana de información compacta, independiente de la ventana del reproductor.
enum AboutMusicaLocal {
    private static var window: NSWindow?

    static func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let size = NSSize(width: 440, height: 380)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Acerca de Música Local"
        window.isReleasedWhenClosed = false
        window.minSize = size
        window.maxSize = size
        window.contentView = NSHostingView(rootView: AboutMusicaLocalView())
        window.setContentSize(size)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutMusicaLocalView: View {
    private var icon: NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 9) {
            Group {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 76, height: 76)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 46, weight: .medium))
                        .frame(width: 76, height: 76)
                }
            }
            .padding(.top, 9)

            Text("Música Local")
                .font(.system(size: 24, weight: .bold))
            Text("Versión 1.0")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 36)
                .padding(.vertical, 4)

            Group {
                Text("Desarrollado por Andrés Báez")
                    .font(.system(size: 13, weight: .semibold))
                Text("Reproductor de música local, gratuito y de código abierto.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                Text("SwiftUI · AppKit · AVFoundation · macOS 12+")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider().padding(.horizontal, 36).padding(.top, 5)

            Group {
                HStack(spacing: 17) {
                    Button("Licencia MIT") { LegalDocuments.open("LICENSE") }
                    Button("Términos") { LegalDocuments.open("TERMINOS_Y_CONDICIONES") }
                    Button("Privacidad") { LegalDocuments.open("PRIVACIDAD") }
                }
                .buttonStyle(.link)
                Text("© 2026 Andrés Báez")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 440, height: 380, alignment: .center)
        .background(AppearanceSurface())
    }
}

/// Los archivos .md se mantienen en Resources, pero se leen como texto dentro
/// de una ventana de Música Local. Nunca se envían a NSWorkspace para abrirlos.
enum LegalDocuments {
    private static var window: NSWindow?
    private static let selection = LegalDocumentSelection()

    static func open(_ file: String) {
        selection.selected = LegalDocumentKind(rawValue: file) ?? .license
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 690, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Documentos legales · Música Local"
        window.minSize = NSSize(width: 490, height: 350)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LegalDocumentsView(selection: selection))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case license = "LICENSE"
    case terms = "TERMINOS_Y_CONDICIONES"
    case privacy = "PRIVACIDAD"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .license: return "Licencia MIT"
        case .terms: return "Términos"
        case .privacy: return "Privacidad"
        }
    }

    var documentTitle: String {
        switch self {
        case .license: return "Licencia MIT"
        case .terms: return "Términos y condiciones"
        case .privacy: return "Política de privacidad"
        }
    }
}

private final class LegalDocumentSelection: ObservableObject {
    @Published var selected: LegalDocumentKind = .license
}

// Lector de Markdown por bloques. SwiftUI en Monterey no presenta bien los
// encabezados y espacios de un documento completo dentro de un solo Text.
// Separar los bloques conserva la jerarquía visual y evita los párrafos pegados.
private struct LegalTextBlock: Identifiable {
    enum Kind: Equatable { case heading1, heading2, heading3, paragraph, quotation, separator, bullet }

    let id: Int
    let kind: Kind
    let content: String

    static func parse(_ markdown: String) -> [LegalTextBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var result: [LegalTextBlock] = []
        var paragraph: [String] = []

        func append(_ kind: Kind, _ content: String) {
            let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty || kind == .separator {
                result.append(LegalTextBlock(id: result.count, kind: kind, content: value))
            }
        }
        func flushParagraph() {
            if !paragraph.isEmpty {
                // Los saltos simples en Markdown unen una misma oración;
                // los dos espacios finales crean un salto visual intencionado.
                var text = ""
                var previousHardBreak = false
                for line in paragraph {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { text += previousHardBreak ? "\n" : " " }
                    text += trimmed
                    previousHardBreak = line.hasSuffix("  ")
                }
                append(.paragraph, text)
                paragraph.removeAll()
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                append(.separator, "")
            } else if trimmed.hasPrefix("### ") {
                flushParagraph()
                append(.heading3, String(trimmed.dropFirst(4)))
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                append(.heading2, String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("# ") {
                flushParagraph()
                append(.heading1, String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                append(.quotation, String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                append(.bullet, String(trimmed.dropFirst(2)))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return result
    }
}

private struct LegalDocumentsView: View {
    @ObservedObject var selection: LegalDocumentSelection

    private var source: String? {
        guard let url = Bundle.main.url(forResource: selection.selected.rawValue, withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Los enlaces relativos a Markdown se mantienen como texto legible;
        // el cambio de documento se realiza en las pestañas de arriba.
        return contents.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+\\.md)\\)",
            with: "$1", options: .regularExpression
        )
    }

    private var blocks: [LegalTextBlock] {
        guard let source = source else { return [] }
        return LegalTextBlock.parse(source)
    }

    @ViewBuilder private func richText(_ content: String) -> some View {
        if let formatted = try? AttributedString(markdown: content) {
            Text(formatted)
                .textSelection(.enabled)
        } else {
            Text(content)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder private func blockView(_ block: LegalTextBlock) -> some View {
        switch block.kind {
        case .heading1:
            richText(block.content)
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, 5)
                .padding(.bottom, 8)
        case .heading2:
            richText(block.content)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 15)
                .padding(.bottom, 3)
        case .heading3:
            richText(block.content)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 9)
        case .paragraph:
            richText(block.content)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        case .quotation:
            HStack(alignment: .top, spacing: 13) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3)
                richText(block.content)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045))
            .cornerRadius(8)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").font(.system(size: 13, weight: .bold))
                richText(block.content)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 9)
        case .separator:
            Divider().padding(.vertical, 12)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "doc.text")
                    .font(.system(size: 19))
                    .foregroundColor(.accentColor)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Documentación legal")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Consulta las condiciones y políticas de Música Local")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Versión 1.0")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 17)

            Picker("Documento", selection: $selection.selected) {
                ForEach(LegalDocumentKind.allCases) { document in
                    Text(document.title).tag(document)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 28)
            .padding(.bottom, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if source != nil {
                        ForEach(blocks) { block in
                            blockView(block)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                            Text("No se encontró el documento en los recursos de la aplicación.")
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 29)
                .padding(.bottom, 42)
                .frame(maxWidth: 740, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id(selection.selected)
        }
        .frame(minWidth: 490, minHeight: 350)
        .background(AppearanceSurface())
    }
}
