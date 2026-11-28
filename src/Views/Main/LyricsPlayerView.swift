import AppKit
import Combine
import SwiftUI

struct LyricsPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let track: Track
    let clock: PlaybackClock
    @ObservedObject var accent: AccentModel
    let isPlaying: Bool
    let position: () -> Double
    let seek: (Double) -> Void
    @AppStorage("lyricsAnimate") private var animate = true

    @State private var result: LyricsStore.Result?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        GeometryReader { geometry in
            let coverSize = min(218, geometry.size.width * 0.26, geometry.size.height * 0.55)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    ArtworkView(url: track.url, size: max(1, coverSize), large: true, corner: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.title2.weight(.semibold)).lineLimit(2)
                        if !track.artist.isEmpty {
                            Text(track.artist).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
                .frame(width: min(300, geometry.size.width * 0.37))
                .frame(maxHeight: .infinity)
                Divider()
                lyricsPane
            }
        }
        .background(LinearGradient(colors: [accent.shown.color.opacity(0.14), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .task(id: [track.id, track.title, track.artist, track.album, String(track.mtime), String(attempt)]) {
            await loadLyrics()
        }
    }

    @ViewBuilder
    private var lyricsPane: some View {
        if let result = result {
            switch result {
            case let .lyrics(lyrics) where lyrics.hasTiming:
                SyncedLyricsView(lyrics: lyrics, trackID: track.id, clock: clock, accent: accent.shown.color,
                                 isPlaying: isPlaying, position: position, seek: seek)
            case let .lyrics(lyrics):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Letra sin marcas de tiempo").font(.caption).foregroundColor(.secondary)
                        Text(lyrics.plainText).font(.title3).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
            case .instrumental:
                VStack(spacing: 10) {
                    Image(systemName: "music.note").font(.system(size: 36, weight: .medium))
                        .foregroundColor(accent.shown.color)
                        .accessibilityHidden(true)
                    Text("Pista instrumental").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                message("No se encontró la letra de esta canción.", retry: true)
            case .missingMetadata:
                message("Se necesita el título y el artista para buscar la letra en línea.")
            }
        } else if let error = error {
            message(error, retry: true)
        } else {
            ProgressView("Buscando la letra…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func message(_ text: String, retry: Bool = false) -> some View {
        VStack(spacing: 12) {
            Text(text).foregroundColor(.secondary).multilineTextAlignment(.center)
            if retry { Button("Volver a buscar") { attempt += 1 } }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadLyrics() async {
        result = nil
        error = nil
        do {
            let duration = clock.duration > 0 ? clock.duration : track.duration
            let loaded = try await LyricsStore.shared.lyrics(for: track, duration: duration, refresh: attempt > 0)
            try Task.checkCancellation()
            withAnimation(reduceMotion || !animate ? nil : .easeInOut(duration: 0.25)) {
                result = loaded
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = (error as? LyricsStore.LookupError)?.localizedDescription
                ?? "No se pudo consultar la letra. Comprueba la conexión."
        }
    }
}

private struct SyncedLyricsView: View {
    let lyrics: Lyrics
    let trackID: String
    let clock: PlaybackClock
    let accent: Color
    let isPlaying: Bool
    let position: () -> Double
    let seek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lyricsFollow") private var follow = true
    @AppStorage("lyricsAnimate") private var animate = true
    @AppStorage("lyricsWords") private var showWords = true
    @AppStorage("lyricsSuspendOnScroll") private var suspendOnScroll = true
    @AppStorage("lyricsOffsets") private var offsets = Data()

    @State private var suspended = false
    @State private var visible = false
    @State private var steps = 0
    @State private var currentLine: Int?
    @State private var currentWord: Int?
    @State private var wordStep = 0

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            Color.clear.frame(height: 1).id(-1)
                            ForEach(lyrics.lines.indices, id: \.self) { index in
                                lyricRow(at: index).equatable().id(index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, geometry.size.height * 0.5)
                    }
                    .background(LyricsScrollObserver(onManualScroll: {
                        if follow && suspendOnScroll { suspended = true }
                    }, onVisibility: { visible = $0 }))
                    .overlay(alignment: .bottomTrailing) {
                        if suspended || !follow {
                            Button("Volver a la línea actual") {
                                suspended = false
                                follow = true
                                updateHighlight()
                                scroll(proxy)
                            }
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                        }
                    }
                    .onAppear {
                        steps = LyricsOffsets.steps(in: offsets, trackID: trackID)
                        updateHighlight()
                    }
                    .onChange(of: offsets) { data in
                        steps = LyricsOffsets.steps(in: data, trackID: trackID)
                        updateHighlight()
                    }
                    .onChange(of: currentLine) { _ in
                        if follow && !suspended { scroll(proxy) }
                    }
                    .onChange(of: visible) { shown in
                        guard shown else { return }
                        updateHighlight()
                        if follow && !suspended { scroll(proxy, animated: false) }
                    }
                    .onChange(of: follow) { enabled in
                        if enabled {
                            suspended = false
                            scroll(proxy)
                        }
                    }
                    .onChange(of: showWords) { _ in updateHighlight() }
                    .onChange(of: isPlaying) { _ in updateHighlight() }
                    .onReceive(clock.$progress.removeDuplicates()) { _ in
                        if visible { updateHighlight() }
                    }
                    .task(id: visible && isPlaying) {
                        guard visible && isPlaying else { return }
                        while !Task.isCancelled {
                            updateHighlight()
                            try? await Task.sleep(nanoseconds: 40_000_000)
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { changeOffset(steps - 1) } label: { Image(systemName: "minus") }
                .disabled(steps <= -240)
                .help("Adelantar la letra 0,25 s (mostrarla antes)")
                .accessibilityLabel("Adelantar la letra")
            Text((Double(steps) / 4).formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + " s")
                .font(.caption.monospacedDigit())
                .accessibilityLabel("Desfase de la letra")
            Button { changeOffset(steps + 1) } label: { Image(systemName: "plus") }
                .disabled(steps >= 240)
                .help("Atrasar la letra 0,25 s (mostrarla después)")
                .accessibilityLabel("Atrasar la letra")
            Button { changeOffset(0) } label: { Image(systemName: "arrow.counterclockwise") }
                .disabled(steps == 0)
                .help("Restablecer el desfase")
                .accessibilityLabel("Restablecer el desfase")
            Spacer(minLength: 2)
            Text("− antes · + después").font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func changeOffset(_ value: Int) {
        steps = value
        offsets = LyricsOffsets.updating(offsets, trackID: trackID, steps: value)
        updateHighlight()
    }

    private func lyricRow(at index: Int) -> LyricRow {
        let line = lyrics.lines[index]
        let active = currentLine == index
        let target = min(max(0, line.time + Double(steps) / 4), max(0, clock.duration))
        return LyricRow(line: line, active: active, past: index < (currentLine ?? 0),
                        showWords: active && showWords, currentWord: active ? currentWord : nil,
                        wordStep: active ? wordStep : 0, target: target, accent: accent, seek: seek)
    }

    private func updateHighlight() {
        let time = position() - Double(steps) / 4
        let index = lyrics.lineIndex(at: time)
        let line = index.map { lyrics.lines[$0] }
        let word = showWords ? line?.wordIndex(at: time) : nil
        var step = 0
        if let line = line, let word = word {
            let segment = line.words[word]
            if let end = segment.end, end > segment.start, !reduceMotion, animate {
                step = min(4, Int(max(0, min(1, (time - segment.start) / (end - segment.start))) * 4))
            } else {
                step = 4
            }
        }
        if currentLine != index { currentLine = index }
        if currentWord != word { currentWord = word }
        if wordStep != step { wordStep = step }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard visible else { return }
        withAnimation(animated && animate && !reduceMotion ? .easeOut(duration: 0.23) : nil) {
            proxy.scrollTo(currentLine ?? -1, anchor: currentLine == nil ? .top : .center)
        }
    }
}

private struct LyricRow: View, Equatable {
    let line: Lyrics.Line
    let active: Bool
    let past: Bool
    let showWords: Bool
    let currentWord: Int?
    let wordStep: Int
    let target: Double
    let accent: Color
    let seek: (Double) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.active == rhs.active && lhs.past == rhs.past && lhs.showWords == rhs.showWords
            && lhs.currentWord == rhs.currentWord && lhs.wordStep == rhs.wordStep && lhs.target == rhs.target
            && lhs.accent == rhs.accent && lhs.line == rhs.line
    }

    var body: some View {
        Button { seek(target) } label: {
            Group {
                if line.isInstrumental {
                    Image(systemName: "music.note")
                } else if active && showWords && !line.words.isEmpty {
                    wordText(line)
                } else {
                    Text(line.text)
                }
            }
            .font(.system(size: 23, weight: .semibold, design: .rounded))
            .foregroundColor(active ? accent : .secondary)
            .opacity(past ? 0.65 : 1)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(accent).opacity(active ? 0.12 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line.isInstrumental ? "Tramo instrumental" : line.text)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help("Saltar a \(fmt(target))")
    }

    private func wordText(_ line: Lyrics.Line) -> Text {
        guard let index = currentWord else { return Text(line.text).foregroundColor(.secondary) }
        let sung = line.words.prefix(index).map(\.text).joined()
        let upcoming = line.words.dropFirst(index + 1).map(\.text).joined()
        return Text(line.prefix).foregroundColor(.secondary)
            + Text(sung).foregroundColor(accent)
            + Text(line.words[index].text).foregroundColor(accent.opacity(0.73 + Double(wordStep) * 0.0675))
            + Text(upcoming).foregroundColor(.secondary)
    }

}

private struct LyricsScrollObserver: NSViewRepresentable {
    let onManualScroll: () -> Void
    let onVisibility: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onManualScroll = onManualScroll
        view.onVisibility = onVisibility
    }

    final class ObserverView: NSView {
        var onManualScroll: (() -> Void)?
        var onVisibility: ((Bool) -> Void)?
        private var monitor: Any?
        private var visibilityObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
            if let observer = visibilityObserver { NotificationCenter.default.removeObserver(observer) }
            monitor = nil
            visibilityObserver = nil
            if let window = window {
                visibilityObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self] _ in self?.publishVisibility() }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] event in
                    guard let self = self, self.window === event.window,
                          self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                    if event.type == .scrollWheel {
                        if event.momentumPhase.isEmpty { self.onManualScroll?() }
                    } else if let content = self.window?.contentView,
                              content.hitTest(content.convert(event.locationInWindow, from: nil)) is NSScroller {
                        self.onManualScroll?()
                    }
                    return event
                }
            }
            publishVisibility()
        }

        deinit {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
            if let observer = visibilityObserver { NotificationCenter.default.removeObserver(observer) }
        }

        private func publishVisibility() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onVisibility?(self.window?.occlusionState.contains(.visible) == true)
            }
        }
    }
}
