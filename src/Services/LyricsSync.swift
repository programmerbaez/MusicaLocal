import Combine
import Foundation

@MainActor
final class LyricsSync: ObservableObject {
    struct Progress {
        let total: Int
        var checked = 0
        var available = 0
    }

    @Published private(set) var progress: Progress?
    @Published private(set) var isRunning = false
    @Published private(set) var completion: String?
    private var task: Task<Void, Never>?

    func start(_ tracks: [Track]) {
        guard !isRunning, !tracks.isEmpty else { return }
        progress = Progress(total: tracks.count)
        completion = nil
        isRunning = true
        task = Task { await synchronize(tracks) }
    }

    func cancel() {
        task?.cancel()
    }

    private func synchronize(_ tracks: [Track]) async {
        defer {
            task = nil
            isRunning = false
        }
        var current = Progress(total: tracks.count)
        do {
            for track in tracks {
                let result = try await LyricsStore.shared.lyrics(for: track, duration: track.duration, requireOfflineCopy: true)
                current.checked += 1
                if case .lyrics = result { current.available += 1 }
                progress = current
            }
            completion = "Sincronización terminada."
        } catch {
            if Task.isCancelled {
                completion = "Sincronización cancelada."
            } else {
                completion = "Sincronización interrumpida. \(error.localizedDescription)"
            }
        }
    }
}
