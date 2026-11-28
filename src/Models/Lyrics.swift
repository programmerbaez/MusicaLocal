import Foundation

struct Lyrics {
    struct Word: Equatable {
        let text: String
        let start: Double
        let end: Double?
    }

    struct Line: Equatable {
        let time: Double
        let text: String
        var end: Double? = nil
        var prefix = ""
        var words: [Word] = []

        var isInstrumental: Bool {
            switch text.lowercased() {
            case "", "[instrumental]", "(instrumental)", "♪", "♫", "♬", "🎵", "🎶": return true
            default: return false
            }
        }

        func wordIndex(at position: Double) -> Int? {
            Lyrics.lastIndex(in: words, at: position, time: \.start)
        }
    }

    let lines: [Line]
    let plainText: String

    init(lrc: String = "", plainText: String = "", timedLines: [Line] = []) {
        lines = timedLines.isEmpty ? Self.parse(lrc) : Self.prepare(timedLines)
        let supplied = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.plainText = !supplied.isEmpty || !lines.isEmpty ? supplied : lrc.components(separatedBy: .newlines)
            .filter { $0.range(of: #"^\s*\[[a-zA-Z]+:[^\]]*\]\s*$"#, options: .regularExpression) == nil }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasTiming: Bool { !lines.isEmpty }
    var isEmpty: Bool { !hasTiming && plainText.isEmpty }

    func lineIndex(at position: Double) -> Int? {
        Self.lastIndex(in: lines, at: position, time: \.time)
    }

    private static func lastIndex<T>(in items: [T], at position: Double, time: KeyPath<T, Double>) -> Int? {
        var low = 0
        var high = items.count
        while low < high {
            let middle = low + (high - low) / 2
            if items[middle][keyPath: time] <= position { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }

    private static let timestamp = try! NSRegularExpression(pattern: #"^\[(\d+):([0-5]?\d)(?:[.:](\d{1,3}))?\]"#)
    private static let wordTimestamp = try! NSRegularExpression(pattern: #"<(\d+):([0-5]?\d)(?:[.:](\d{1,3}))?>"#)

    private static func seconds(_ match: NSTextCheckingResult, in source: String) -> Double? {
        guard let minutes = Range(match.range(at: 1), in: source),
              let seconds = Range(match.range(at: 2), in: source),
              let wholeMinutes = Double(source[minutes]), let wholeSeconds = Double(source[seconds]) else { return nil }
        let fraction = Range(match.range(at: 3), in: source).flatMap { Double("0." + source[$0]) } ?? 0
        let time = wholeMinutes * 60 + wholeSeconds + fraction
        return time.isFinite ? time : nil
    }

    private static func parse(_ lrc: String) -> [Line] {
        let rows = lrc.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}")))
        }
        let offset = rows.lazy.compactMap { row -> Int? in
            guard row.lowercased().hasPrefix("[offset:"), row.hasSuffix("]") else { return nil }
            return Int(row.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        let adjustment = Double(offset) / 1000

        var lines: [Line] = []
        for row in rows {
            var remaining = row
            var times: [Double] = []
            while let match = timestamp.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
                  let full = Range(match.range, in: remaining) {
                if let time = seconds(match, in: remaining) { times.append(time) }
                remaining.removeSubrange(full)
            }
            guard let first = times.first else { continue }
            let source = remaining.trimmingCharacters(in: .whitespaces)
            let matches = wordTimestamp.matches(in: source, range: NSRange(source.startIndex..., in: source))
            let markers = matches.compactMap { match -> (range: Range<String.Index>, time: Double)? in
                guard let range = Range(match.range, in: source), let time = seconds(match, in: source) else { return nil }
                return (range, time)
            }
            let text = wordTimestamp.stringByReplacingMatches(in: source,
                range: NSRange(source.startIndex..., in: source), withTemplate: "")
            let ordered = zip(markers, markers.dropFirst()).allSatisfy { $0.0.time <= $0.1.time }
            let prefix = markers.first.map { String(source[..<$0.range.lowerBound]) } ?? ""
            for time in times {
                let lineTime = max(0, time - adjustment)
                var line = Line(time: lineTime, text: text)
                if ordered, markers.first.map({ $0.time >= first }) == true {
                    let shift = time - first - adjustment
                    line.prefix = prefix
                    for (index, marker) in markers.enumerated() {
                        let next = index + 1 < markers.count ? markers[index + 1] : nil
                        let word = String(source[marker.range.upperBound..<(next?.range.lowerBound ?? source.endIndex)])
                        guard !word.isEmpty else { continue }
                        line.words.append(Word(text: word, start: max(lineTime, marker.time + shift),
                                               end: next.map { max(lineTime, $0.time + shift) }))
                    }
                }
                lines.append(line)
            }
        }
        return prepare(lines)
    }

    private static func prepare(_ source: [Line]) -> [Line] {
        // Swift conserva el orden de las filas con la misma marca.
        var lines = source
        lines.sort { $0.time < $1.time }
        var prepared: [Line] = []
        if let first = lines.first, first.time > 0 { prepared.append(Line(time: 0, text: "")) }
        var coveredUntil = 0.0
        for (index, line) in lines.enumerated() {
            prepared.append(line)
            guard let end = line.end, end > line.time else { continue }
            coveredUntil = max(end, coveredUntil)
            if index + 1 == lines.count || coveredUntil < lines[index + 1].time {
                prepared.append(Line(time: coveredUntil, text: ""))
            }
        }
        return prepared
    }
}
