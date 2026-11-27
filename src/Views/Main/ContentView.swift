// Música Local — ContentView
// Código extraído sin alterar la lógica de MusicaLocal.swift.
import SwiftUI
import AVFoundation
import AppKit
import ImageIO
import MediaPlayer
import QuartzCore

// MARK: - Vista principal

struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var p: Player
    let accent: AccentModel
    @State private var creatingPlaylist = false
    @State private var playlistName = ""
    @State private var creationError: String?
    @State private var playlistError: String?

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(accent: accent, onCreatePlaylist: beginPlaylistCreation) { path in
                editPlaylist { try p.removeFromActivePlaylist(path: path) }
            }
            Divider()

            if let playlist = p.activePlaylist,
               playlist.trackPaths.count == p.unavailablePlaylistPaths.count {
                emptyPlaylist(playlist)
            } else if p.tracks.isEmpty {
                emptyState
            } else if p.visible.isEmpty {
                noResults
            } else {
                libraryList
            }

            Divider()
            PlayerBar(p: p, clock: p.clock, accent: accent)
        }
        .foregroundColor(scheme == .light ? AppearancePalette.charcoal : .primary)
        .background(AccentBackground())
        .background(MainWindowChrome(player: p))
        .ignoresSafeArea(.container, edges: .top)
        .symbolRenderingMode(.hierarchical)
        .frame(minWidth: 780, idealWidth: 940, minHeight: 500, idealHeight: 640)
        .sheet(isPresented: $creatingPlaylist) { playlistForm }
        .alert("No se pudo actualizar la lista", isPresented: Binding(
            get: { playlistError != nil },
            set: { if !$0 { playlistError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { playlistError = nil }
        } message: {
            Text(playlistError ?? "")
        }
        .onAppear {
            // Que el buscador no se quede con el foco al arrancar (bloquearía los atajos y las flechas)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { resignFocus() }
        }
    }

    private func beginPlaylistCreation() {
        playlistName = ""
        creationError = nil
        creatingPlaylist = true
    }

    private var playlistForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nueva lista de reproducción").font(.headline)
            TextField("Nombre de la lista", text: $playlistName)
                .onSubmit(createPlaylist)
            if let error = creationError {
                Text(error).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancelar") { creatingPlaylist = false }
                    .keyboardShortcut(.cancelAction)
                Button("Crear", action: createPlaylist)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func createPlaylist() {
        do {
            try p.createPlaylist(named: playlistName)
            creatingPlaylist = false
        } catch {
            creationError = error.localizedDescription
        }
    }

    private func editPlaylist(_ edit: () throws -> Void) {
        do { try edit() }
        catch { playlistError = error.localizedDescription }
    }

    private func emptyPlaylist(_ playlist: Playlist) -> some View {
        VStack(spacing: 8) {
            Text(playlist.trackPaths.isEmpty ? "Esta lista está vacía" : "No hay canciones disponibles")
                .font(.title3.weight(.semibold))
            if playlist.trackPaths.isEmpty {
                Text("Desde la biblioteca, haz clic secundario en una canción y elige «Añadir a una lista».")
                    .foregroundColor(.secondary)
            }
            Button("Volver a la biblioteca") { p.selectPlaylist(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var libraryList: some View {
        GeometryReader { geo in
            let cols = ColumnLayout(total: geo.size.width)
            VStack(spacing: 0) {
                ColumnHeader(cols: cols)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(p.visible.enumerated()), id: \.element.id) { i, t in
                                TrackRow(track: t,
                                         index: i,
                                         cols: cols,
                                         isCurrent: p.nowPlaying?.id == t.id,
                                         isPlaying: p.isPlaying,
                                         isSelected: p.selectedID == t.id,
                                         accent: accent)
                                    .onTapGesture(count: 2) {
                                        resignFocus()
                                        p.selectedID = t.id
                                        p.play(t)
                                    }
                                    .onTapGesture {
                                        resignFocus()
                                        p.selectedID = t.id
                                    }
                                    .contextMenu {
                                        Button { p.play(t) } label: {
                                            Label("Reproducir", systemImage: "play.fill")
                                        }
                                        Button { p.playNext(t) } label: {
                                            Label("Reproducir a continuación", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                        Button { p.addToQueue(t) } label: {
                                            Label("Añadir a la cola", systemImage: "text.badge.plus")
                                        }
                                        if !p.playlists.isEmpty {
                                            Menu("Añadir a una lista") {
                                                ForEach(p.playlists) { playlist in
                                                    Button(playlist.name) {
                                                        editPlaylist { try p.addToPlaylist(t, playlistID: playlist.id) }
                                                    }
                                                    .disabled(playlist.trackPaths.contains(t.id))
                                                }
                                            }
                                        }
                                        if p.activePlaylistID != nil {
                                            Button {
                                                editPlaylist { try p.removeFromActivePlaylist(path: t.id) }
                                            } label: {
                                                Label("Quitar de esta lista", systemImage: "minus.circle")
                                            }
                                        }
                                        Divider()
                                        Button { NSWorkspace.shared.activateFileViewerSelecting([t.url]) } label: {
                                            Label("Mostrar en Finder", systemImage: "folder")
                                        }
                                    }
                            }
                        }
                    }
                    .onChange(of: p.scrollRequest) { req in
                        guard let req = req else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(req.id, anchor: req.center ? .center : nil)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            if p.isScanning {
                ProgressView()
                Text("Buscando canciones…").foregroundColor(.secondary)
            } else if let missing = p.missingFolder {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44)).foregroundColor(.orange)
                Text("No se encontró la carpeta guardada").font(.title3.weight(.semibold))
                Text(missing).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle).padding(.horizontal, 40)
                chooseButton
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48)).foregroundColor(.secondary)
                Text(p.folderURL == nil ? "Tu biblioteca está vacía" : "No hay canciones en esta carpeta")
                    .font(.title3.weight(.semibold))
                Text("Elige una carpeta con tu música para empezar.")
                    .foregroundColor(.secondary)
                chooseButton
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chooseButton: some View {
        Button { openSettings() } label: {
            Label("Configurar carpeta en Ajustes…", systemImage: "gearshape")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 6)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40)).foregroundColor(.secondary)
            Text("Sin resultados").font(.title3.weight(.semibold))
            Text("No hay coincidencias para “\(p.query)”.").foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

