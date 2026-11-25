// Música Local — MiniProgress
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

struct MiniProgress: View {
    @ObservedObject var player: Player
    @ObservedObject var clock: PlaybackClock
    let showTimes: Bool
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(
                get: { dragging ? dragValue : min(clock.progress, max(clock.duration, 1)) },
                set: { dragValue = $0 }
            ), in: 0...max(clock.duration, 1), onEditingChanged: { editing in
                if editing {
                    dragging = true
                    dragValue = clock.progress
                } else {
                    player.seek(dragValue)
                    dragging = false
                }
            })
            .disabled(player.nowPlaying == nil)
            .accessibilityLabel("Progreso de reproducción")
            if showTimes {
                HStack {
                    Text(fmt(dragging ? dragValue : clock.progress))
                    Spacer()
                    Text("−" + fmt(max(0, clock.duration - (dragging ? dragValue : clock.progress))))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
    }
}

