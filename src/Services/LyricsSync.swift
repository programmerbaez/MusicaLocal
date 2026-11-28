import Combine
import Foundation

@MainActor
final class LyricsSync: ObservableObject {
    struct Progress {
        let total: Int
        var checked = 0
        var available = 0
        var failed = 0
        var pending: Int { total - checked }
    }

    @Published private(set) var progress: Progress?
    @Published private(set) var isRunning = false
    @Published private(set) var completion: String?
    private(set) var failedTracks: [String: String] = [:]
    private var task: Task<Void, Never>?
    private let store: LyricsStore

    init(store: LyricsStore = .shared) { self.store = store }

    func start(_ tracks: [Track]) {
        guard !isRunning, !tracks.isEmpty else { return }
        progress = Progress(total: tracks.count)
        completion = nil
        failedTracks.removeAll()
        isRunning = true
        task = Task { await synchronize(tracks) }
    }

    func cancel() { task?.cancel() }

    private func synchronize(_ tracks: [Track]) async {
        defer {
            task = nil
            isRunning = false
        }
        var current = Progress(total: tracks.count)
        for track in tracks {
            if Task.isCancelled { break }
            do {
                let result = try await lookup(track)
                if result.hasLyrics { current.available += 1 }
            } catch {
                if Task.isCancelled { break }
                failedTracks[track.id] = error.localizedDescription
                current.failed += 1
            }
            current.checked += 1
            progress = current
        }
        if Task.isCancelled {
            completion = "Sincronización cancelada. Puedes continuar cuando quieras."
        } else if current.failed > 0 {
            completion = "Sincronización terminada con fallos. Vuelve a sincronizar para reintentarlos."
        } else {
            completion = "Sincronización terminada."
        }
    }

    private func lookup(_ track: Track) async throws -> LyricsStore.Result {
        for delay in [1, 2] {
            do {
                return try await store.lyrics(for: track, duration: track.duration, requireOfflineCopy: true)
            } catch {
                try Task.checkCancellation()
                switch error {
                case LyricsStore.LookupError.rateLimited, LyricsStore.LookupError.service, is URLError:
                    try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                default: throw error
                }
            }
        }
        return try await store.lyrics(for: track, duration: track.duration, requireOfflineCopy: true)
    }
}
