// Música Local — ArtworkView
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

struct ArtworkView: View {
    let url: URL?
    var size: CGFloat
    var large: Bool = false
    var corner: CGFloat = 5

    @State private var image: NSImage?
    @State private var token: ArtworkStore.Token = 0
    @State private var loadedURL: URL?

    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.primary.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        .onAppear { load() }
        .onDisappear { ArtworkStore.shared.cancel(token) }
        .onChange(of: url) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: ArtworkStore.didInvalidateArtwork)) { event in
            if event.object as? String == url?.path { load() }
        }
    }

    private func load() {
        // Invalida cualquier petición anterior antes de cambiar de canción.
        ArtworkStore.shared.cancel(token)
        token = 0
        loadedURL = nil
        image = nil  // No mostrar la carátula de la pista anterior durante la carga.

        guard let target = url else { return }
        loadedURL = target
        token = ArtworkStore.shared.request(url: target, large: large) { img in
            // Ignora respuestas que ya no pertenecen a la canción visible.
            guard loadedURL == target else { return }
            image = img
        }
    }
}

