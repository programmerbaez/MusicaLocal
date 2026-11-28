import SwiftUI
import AppKit

struct MetadataEditorView: View {
    let track: Track
    @ObservedObject var player: Player
    let accent: AccentModel
    @Environment(\.dismiss) private var dismiss

    @State private var writeUnavailable = false
    @State private var revision: MetadataWriter.Revision?
    @State private var original: [MusicTag: String] = [:]
    @State private var proposal: [MusicTag: String] = [:]
    @State private var selected: Set<MusicTag> = []
    @State private var matches: [MusicMatch] = []
    @State private var editions: [MusicEdition] = []
    @State private var recordingID: UUID?
    @State private var editionID: UUID?
    @State private var cover: MetadataCover?
    @State private var includeCover = false
    @State private var coverStatus = ""
    @State private var userKey = ""
    @State private var status = ""
    @State private var backup: URL?
    @State private var job: Task<Void, Never>?
    @State private var writing = false
    @State private var committing = false
    @State private var didSearch = false

    private var supportsWriting: Bool { MetadataWriter.supports(track.url) && !writeUnavailable }
    private var busy: Bool { job != nil }
    private var closedForPlayback: Bool { !player.isOpenForPlayback(track.url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actualizar metadatos").font(.title2)
            Text(track.title).font(.headline).lineLimit(1).help(track.title)
            if !supportsWriting {
                Text("La edición permanente no está disponible para este formato. Puedes identificar la grabación y consultar sus ediciones.")
                    .foregroundColor(.secondary)
            }
            identification
            Divider()
            comparison
            if !status.isEmpty { Text(status).fixedSize(horizontal: false, vertical: true) }
            if let backup = backup {
                Button("Mostrar copia de recuperación en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([backup])
                }
            }
            footer
        }
        .padding(22)
        .frame(width: 760, height: 710)
        .background(AppearanceSurface())
        .interactiveDismissDisabled(writing)
        .onDisappear { if !writing { job?.cancel() } }
        .task {
            let result = await inspect()
            guard !Task.isCancelled else { return }
            revision = result.0
            original = result.1
            writeUnavailable = result.2
        }
    }

    private func inspect() async -> (MetadataWriter.Revision?, [MusicTag: String], Bool) {
        let version = try? MetadataWriter.revision(track.url)
        let values = try? MetadataWriter.readTags(track.url)
        let after = try? MetadataWriter.revision(track.url)
        let display = values ?? [.title: track.title, .artist: track.artist, .album: track.album]
        return (version == after ? version : nil, display, values == nil)
    }

    private var identification: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Al pulsar Identificar canción se envían una huella acústica y la duración a AcoustID. MusicBrainz y Cover Art Archive reciben los identificadores de las opciones elegidas.")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                SecureField("Clave de usuario de AcoustID", text: $userKey)
                    .textFieldStyle(.roundedBorder)
                    .help("La clave se usa solo en esta ventana. AcoustID la exige desde enero de 2027.")
                Button(didSearch ? "Buscar nuevamente" : "Identificar canción") { identify() }
                    .disabled(busy || backup != nil)
                if busy && !committing {
                    Button(writing ? "Cancelar guardado" : "Cancelar búsqueda") { job?.cancel() }
                }
                if busy { ProgressView().controlSize(.small) }
            }
            if !matches.isEmpty {
                Picker("Grabación", selection: Binding(get: { recordingID }, set: { selectRecording($0) })) {
                    Text("Seleccionar grabación…").tag(UUID?.none)
                    ForEach(matches) { match in
                        Text(matchLabel(match)).tag(Optional(match.id))
                    }
                }
                .disabled(busy || backup != nil)
            }
            if recordingID != nil {
                Picker("Edición del álbum", selection: Binding(get: { editionID }, set: { selectEdition($0) })) {
                    Text("Conservar datos del álbum").tag(UUID?.none)
                    ForEach(editions) { edition in
                        Text(editionLabel(edition)).tag(Optional(edition.id))
                    }
                }
                .disabled(busy || backup != nil)
            }
        }
    }

    private func matchLabel(_ match: MusicMatch) -> String {
        let duration = match.duration.map { " · \(fmt(Double($0)))" } ?? ""
        return "\(match.title) — \(match.artist)\(duration) · AcoustID \(match.score.formatted(.percent.precision(.fractionLength(0)))) · \(match.id.uuidString.prefix(8))"
    }

    private func editionLabel(_ edition: MusicEdition) -> String {
        let title = edition.tags[.album] ?? ""
        let disc = edition.tags[.disc] ?? "?"
        let track = edition.tags[.track] ?? "?"
        return "\(title) · \(edition.detail) · disco \(disc), pista \(track) · \(edition.releaseID.uuidString.prefix(8))"
    }

    private var comparison: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Información actual").font(.headline)
                        ArtworkView(url: track.url, size: 100, large: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Información propuesta").font(.headline)
                        if let cover = cover, let image = NSImage(data: cover.data) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 100, height: 100)
                            Toggle("Incrustar portada frontal", isOn: $includeCover)
                        } else {
                            Text(coverStatus.isEmpty ? "Conservar portada actual" : coverStatus)
                                .foregroundColor(.secondary).frame(height: 100, alignment: .center)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(MusicTag.allCases) { tag in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.label).font(.caption).foregroundColor(.secondary)
                            Text(original[tag].flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                                .lineLimit(2).help(original[tag] ?? "")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Toggle(isOn: selection(for: tag)) { Text("Actualizar \(tag.label)") }
                                .labelsHidden()
                            TextField(tag.label, text: Binding(
                                get: { proposal[tag] ?? "" },
                                set: { proposal[tag] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.trailing, 10)
        }
        .disabled(writing || backup != nil)
    }

    private func selection(for tag: MusicTag) -> Binding<Bool> {
        Binding(get: { selected.contains(tag) }, set: {
            if $0 { selected.insert(tag) } else { selected.remove(tag) }
        })
    }

    private var changes: [MusicTag: String] {
        proposal.reduce(into: [:]) { result, item in
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if selected.contains(item.key), !value.isEmpty, value != original[item.key] { result[item.key] = value }
        }
    }

    private var footer: some View {
        HStack {
            if supportsWriting && !closedForPlayback && backup == nil {
                Button("Detener esta canción") { player.closePlaybackForMetadata(track.url) }
                    .disabled(writing)
            }
            Spacer()
            if backup == nil {
                Button("Conservar metadatos actuales") { dismiss() }
                    .disabled(writing)
                Button("Cancelar", role: .cancel) { dismiss() }
                    .disabled(writing)
                Button("Aplicar cambios") { save() }
                    .disabled(!supportsWriting || !closedForPlayback || busy || revision == nil ||
                              player.isScanning || (changes.isEmpty && (!includeCover || cover == nil)))
            } else {
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @MainActor
    private func identify() {
        let key = userKey.trimmingCharacters(in: .whitespacesAndNewlines)
        didSearch = true
        matches = []
        recordingID = nil
        editions = []
        clearProposal()
        start("Calculando huella y buscando coincidencias…") {
            let results = try await OnlineMusicIdentification.shared.identify(track.url, userKey: key)
            try Task.checkCancellation()
            matches = results
            status = results.isEmpty ? "No se encontraron coincidencias." : "Selecciona una grabación para revisar sus ediciones."
        }
    }

    @MainActor
    private func selectRecording(_ id: UUID?) {
        recordingID = id
        editions = []
        clearProposal()
        guard let id = id, let match = matches.first(where: { $0.id == id }) else { return }
        proposal = recordingTags(match)
        start("Buscando ediciones en MusicBrainz…") {
            let releases = try await OnlineMusicIdentification.shared.editions(for: id)
            try Task.checkCancellation()
            editions = releases
            status = releases.isEmpty ? "No se encontraron ediciones para esta grabación." :
                "Elige una edición si quieres actualizar los datos del álbum o la portada."
        }
    }

    @MainActor
    private func selectEdition(_ id: UUID?) {
        editionID = id
        cover = nil
        includeCover = false
        coverStatus = ""
        selected = []
        guard let edition = editions.first(where: { $0.id == id }) else {
            if let match = matches.first(where: { $0.id == recordingID }) { proposal = recordingTags(match) }
            return
        }
        proposal = edition.tags
        start("Descargando portada de la edición elegida…") {
            do {
                let image = try await OnlineMusicIdentification.shared.cover(for: edition.releaseID)
                try Task.checkCancellation()
                cover = image
                coverStatus = image == nil ? "No se encontró portada" : ""
                status = ""
            } catch {
                coverStatus = "Portada sin descargar"
                throw error
            }
        }
    }

    private func recordingTags(_ match: MusicMatch) -> [MusicTag: String] {
        [.title: match.title, .artist: match.artist, .recording: match.id.uuidString.lowercased()]
    }

    private func clearProposal() {
        editionID = nil
        proposal = [:]
        selected = []
        cover = nil
        includeCover = false
        coverStatus = ""
    }

    @MainActor
    private func start(_ message: String, operation: @escaping @MainActor () async throws -> Void) {
        guard job == nil else { return }
        status = message
        job = Task { @MainActor in
            do { try await operation() }
            catch {
                if Task.isCancelled { status = "Operación cancelada." }
                else if let network = error as? URLError {
                    status = "No se pudo completar la conexión. \(network.localizedDescription)"
                } else { status = error.localizedDescription }
            }
            job = nil
        }
    }

    @MainActor
    private func save() {
        guard let revision = revision, !busy else { return }
        let tags = changes
        let image = includeCover ? cover : nil
        let oldArtworkKey = ArtworkDisk.key(for: track.url)
        writing = true
        start("Verificando y guardando una copia temporal…") {
            var reserved = false
            do {
                let recovery = try await MetadataWriter.write(to: track.url, expected: revision, changes: tags, cover: image, beforeCommit: {
                    try player.beginMetadataReplacement(track.url)
                    reserved = true
                    committing = true
                })
                let updated = await reloadTrack()
                ArtworkDisk.remove(oldArtworkKey)
                ArtworkStore.shared.invalidate(track.url)
                accent.invalidateArtwork(for: updated)
                player.finishMetadataReplacement(updated)
                backup = recovery
                status = "Metadatos guardados en el archivo musical."
                committing = false
                writing = false
            } catch {
                if reserved { player.finishMetadataReplacement(nil) }
                committing = false
                writing = false
                throw error
            }
        }
    }

    private func reloadTrack() async -> Track {
        var refreshed = Player.readTrack(track)
        refreshed.mtime = (try? track.url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? refreshed.mtime
        return refreshed
    }
}
