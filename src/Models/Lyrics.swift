import Foundation

struct Lyrics {
    struct Line {
        let time: Double
        let text: String
    }

    let lines: [Line]
    let plainText: String

    init(lrc: String = "", plainText: String = "") {
        lines = Self.parse(lrc)
        self.plainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasTiming: Bool { lines.contains { !$0.text.isEmpty } }
    var isEmpty: Bool { !hasTiming && plainText.isEmpty }

    func lineIndex(at position: Double) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let middle = low + (high - low) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }

    private static let timestamp = try! NSRegularExpression(pattern: #"^\[(\d+):([0-5]?\d)(?:[.:](\d{1,3}))?\]"#)

    private static func parse(_ lrc: String) -> [Line] {
        let rows = lrc.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}")))
        }
        let offset = rows.lazy.compactMap { row -> Int? in
            guard row.lowercased().hasPrefix("[offset:"), row.hasSuffix("]") else { return nil }
            return Int(row.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces))
        }.first ?? 0

        var lines: [Line] = []
        for row in rows {
            var remaining = row
            var times: [Double] = []
            while let match = timestamp.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
                  let full = Range(match.range, in: remaining),
                  let minutes = Range(match.range(at: 1), in: remaining),
                  let seconds = Range(match.range(at: 2), in: remaining),
                  let wholeMinutes = Double(remaining[minutes]), let wholeSeconds = Double(remaining[seconds]) {
                let fraction = Range(match.range(at: 3), in: remaining)
                    .flatMap { Double("0." + remaining[$0]) } ?? 0
                let time = wholeMinutes * 60 + wholeSeconds + fraction - Double(offset) / 1000
                if time.isFinite { times.append(max(0, time)) }
                remaining.removeSubrange(full)
            }
            let text = remaining.trimmingCharacters(in: .whitespaces)
            lines.append(contentsOf: times.map { Line(time: $0, text: text) })
        }
        return lines.sorted { $0.time < $1.time }
    }
}
