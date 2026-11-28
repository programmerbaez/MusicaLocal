import Foundation

/// Lee los bloques de tiempos que LRCLIB publica en su Lyricsfile 1.0.
/// Si una representación YAML no se reconoce, el servicio conserva el LRC de la respuesta.
enum LyricsfileTiming {
    private struct Segment {
        var text: String?
        var start: Double?
        var end: Double?

        mutating func read(_ field: String) {
            let pair = field.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return }
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            switch pair[0] {
            case "text": text = LyricsfileTiming.scalar(value)
            case "start_ms": start = LyricsfileTiming.seconds(value)
            case "end_ms": end = LyricsfileTiming.seconds(value)
            default: break
            }
        }
    }

    static func parse(_ source: String) -> [Lyrics.Line] {
        var inside = false
        var lineIndent: Int?
        var wordListIndent: Int?
        var line = Segment()
        var word = Segment()
        var words: [Lyrics.Word] = []
        var result: [Lyrics.Line] = []
        var readingWord = false
        var invalidWords = false
        var encounteredLine = false
        var invalidLine = false

        func finishWord() {
            guard readingWord else { return }
            defer { word = Segment(); readingWord = false }
            guard let text = word.text, let start = word.start, !text.isEmpty,
                  word.end.map({ $0 >= start }) ?? true else {
                invalidWords = true
                return
            }
            words.append(Lyrics.Word(text: text, start: start, end: word.end))
        }

        func finishLine() {
            finishWord()
            defer {
                line = Segment()
                words.removeAll(keepingCapacity: true)
                invalidWords = false
                wordListIndent = nil
            }
            guard let text = line.text, let start = line.start else {
                if encounteredLine { invalidLine = true }
                return
            }
            let ordered = zip(words, words.dropFirst()).allSatisfy { $0.0.start <= $0.1.start }
            let timed = !invalidWords && ordered && words.first.map({ $0.start >= start }) == true
                && words.map(\.text).joined() == text
            let end = line.end.flatMap { $0 >= start ? $0 : nil }
            result.append(Lyrics.Line(time: start, text: text, end: end, words: timed ? words : []))
        }

        for row in source.split(whereSeparator: \.isNewline) {
            let indent = row.prefix(while: { $0 == " " }).count
            let field = String(row.dropFirst(indent))
            if !inside {
                if indent == 0 && field.trimmingCharacters(in: .whitespaces) == "lines:" { inside = true }
                continue
            }
            if field.hasPrefix("#") || field.isEmpty { continue }
            let item = field == "-" || field.hasPrefix("- ")
            if lineIndent == nil && item { lineIndent = indent }
            if indent == 0 && !item { break }
            guard let lineIndent = lineIndent, indent >= lineIndent else { break }
            if item && indent == lineIndent {
                finishLine()
                encounteredLine = true
                line.read(String(field.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if field == "words:" && indent > lineIndent {
                wordListIndent = indent
            } else if item, let wordListIndent = wordListIndent, indent >= wordListIndent {
                finishWord()
                readingWord = true
                word.read(String(field.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if let depth = wordListIndent, indent > depth, readingWord {
                word.read(field)
            } else {
                if wordListIndent != nil {
                    finishWord()
                    wordListIndent = nil
                }
                line.read(field)
            }
        }
        finishLine()
        // Si falta una línea que el documento anunciaba, es más fiable usar el LRC completo.
        return !invalidLine && result.contains(where: { !$0.words.isEmpty }) ? result : []
    }

    private static func seconds(_ value: String) -> Double? {
        guard let milliseconds = Int(value), milliseconds >= 0 else { return nil }
        return Double(milliseconds) / 1000
    }

    private static func scalar(_ value: String) -> String? {
        if value.hasPrefix("'") {
            guard value.count >= 2, value.hasSuffix("'") else { return nil }
            return value.dropFirst().dropLast().replacingOccurrences(of: "''", with: "'")
        }
        if value.hasPrefix("\"") {
            return try? JSONDecoder().decode(String.self, from: Data(value.utf8))
        }
        guard value.first.map({ !"|>&*!{[~".contains($0) }) ?? false,
              !value.contains(" #") else { return nil }
        return value
    }
}
