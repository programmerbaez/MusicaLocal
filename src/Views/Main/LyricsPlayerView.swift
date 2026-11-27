import Combine
import SwiftUI

struct LyricsPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let track: Track
    let clock: PlaybackClock
    @ObservedObject var accent: AccentModel
    let seek: (Double) -> Void

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
                    .transition(.opacity)
            }
        }
        .background(LinearGradient(colors: [accent.shown.color.opacity(0.14), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .task(id: [track.title, track.artist, track.album, String(attempt)]) {
            await loadLyrics()
        }
    }

    @ViewBuilder
    private var lyricsPane: some View {
        if let result = result {
            switch result {
            case let .lyrics(lyrics) where lyrics.hasTiming:
                SyncedLyricsView(lyrics: lyrics, clock: clock, accent: accent.shown.color, seek: seek)
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
            let loaded = try await LyricsStore.shared.lyrics(for: track, duration: duration)
            try Task.checkCancellation()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
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
    let clock: PlaybackClock
    let accent: Color
    let seek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentLine: Int?

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        Color.clear.frame(height: 1).id(-1)
                        ForEach(lyrics.lines.indices, id: \.self) { index in
                            lyricRow(at: index).id(index)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, geometry.size.height * 0.5)
                }
                .onReceive(clock.$progress.removeDuplicates()) { position in
                    updateLine(for: position, proxy: proxy)
                }
            }
        }
    }

    private func lyricRow(at index: Int) -> some View {
        let line = lyrics.lines[index]
        let active = currentLine == index
        return Button {
            seek(min(line.time, max(0, clock.duration)))
        } label: {
            Group {
                if line.isInstrumental {
                    Image(systemName: "music.note")
                } else {
                    Text(line.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 23, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .opacity(active ? 1 : 0.57)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(accent).opacity(active ? 0.20 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line.isInstrumental ? "Tramo instrumental" : line.text)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help("Saltar a \(fmt(line.time))")
    }

    private func updateLine(for position: Double, proxy: ScrollViewProxy) {
        let index = lyrics.lineIndex(at: position)
        guard currentLine != index else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.30)) {
            currentLine = index
            proxy.scrollTo(index ?? -1, anchor: index == nil ? .top : .center)
        }
    }
}
