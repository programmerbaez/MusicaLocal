import Foundation
import Combine
import AppKit

struct ReleaseVersion: Comparable, CustomStringConvertible {
    private let components: [Int]

    init?(_ text: String) {
        let value = text.hasPrefix("v") || text.hasPrefix("V") ? text.dropFirst() : text[...]
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(part)
        }
        guard numbers.count == parts.count else { return nil }
        components = numbers.count == 2 ? numbers + [0] : numbers
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    var description: String {
        let displayed = components[2] == 0 ? Array(components.prefix(2)) : components
        return displayed.map(String.init).joined(separator: ".")
    }

    var archiveVersion: String { components.map(String.init).joined(separator: ".") }
}

struct GitHubMusicRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let state: String
        let digest: String?
    }

    let tag_name: String
    let name: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var version: ReleaseVersion? {
        if let version = ReleaseVersion(tag_name) { return version }
        // La primera release usa la etiqueta de compatibilidad macOS12+.
        guard tag_name == "macOS12+", let name = name, name.hasPrefix("MusicaLocal ") else { return nil }
        return ReleaseVersion(String(name.dropFirst("MusicaLocal ".count)))
    }

    func archive(for version: ReleaseVersion) -> UpdateInstaller.Archive? {
        let prefix = "/programmerbaez/MusicaLocal/releases/download/"
        let names = ["MusicaLocal V\(version.archiveVersion).zip", "MusicaLocal.V\(version.archiveVersion).zip",
                     "MusicaLocal-v\(version.archiveVersion).zip",
                     "MusicaLocal-v\(version).zip"]
        for name in names {
            guard let asset = assets.first(where: { $0.name == name && $0.state == "uploaded" }),
                  let digest = asset.digest, digest.hasPrefix("sha256:"),
                  digest.dropFirst(7).count == 64, digest.dropFirst(7).allSatisfy(\.isHexDigit)
            else { continue }
            let url = asset.browser_download_url
            guard url.scheme == "https", url.host == "github.com", url.user == nil,
                  url.password == nil, url.port == nil, url.path == prefix + tag_name + "/" + name
            else { continue }
            return UpdateInstaller.Archive(url: url, sha256: String(digest.dropFirst(7)).lowercased(), version: version)
        }
        return nil
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum Status {
        case idle, upToDate, available(UpdateInstaller.Archive), missingArchive(ReleaseVersion)
        case failed(String), installed(ReleaseVersion)
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var archive: UpdateInstaller.Archive? = nil
    }

    @Published var notice: Notice?
    @Published private(set) var installing = false
    @Published private(set) var checking = false
    @Published private(set) var status: Status = .idle
    let installedVersion = AppVersion.current
    private var checkedAtLaunch = false
    private var reportResult = false
    private var showAvailabilityNotice = false

    func checkAutomatically() {
        guard !checkedAtLaunch else { return }
        checkedAtLaunch = true
        check(manual: false)
    }

    func check(manual: Bool = true, notifyAvailability: Bool = true) {
        guard !installing else { return }
        reportResult = reportResult || manual
        showAvailabilityNotice = showAvailabilityNotice || notifyAvailability
        guard !checking else { return }
        checking = true
        Task { await fetchLatestRelease() }
    }

    private func fetchLatestRelease() async {
        defer {
            checking = false
            reportResult = false
            showAvailabilityNotice = false
        }
        let endpoint = URL(string: "https://api.github.com/repos/programmerbaez/MusicaLocal/releases/latest")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MusicaLocal", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200:
                let release = try JSONDecoder().decode(GitHubMusicRelease.self, from: data)
                present(release)
            case 404:
                report("No se encontró una versión estable pública en GitHub.")
            case 403, 429:
                report("GitHub limitó temporalmente las consultas. Inténtalo más tarde.")
            default:
                report("GitHub no devolvió una respuesta válida. Inténtalo más tarde.")
            }
        } catch {
            report("No se pudo consultar la versión en GitHub. Comprueba la conexión e inténtalo de nuevo.")
        }
    }

    private func present(_ release: GitHubMusicRelease) {
        guard let installedText = installedVersion,
              let installed = ReleaseVersion(installedText),
              !release.draft, !release.prerelease,
              let latest = release.version else {
            report("No se pudo determinar la versión de la aplicación o de la publicación en GitHub.")
            return
        }
        if latest > installed {
            guard let archive = release.archive(for: latest) else {
                status = .missingArchive(latest)
                if showAvailabilityNotice {
                    notice = Notice(title: "Actualización sin instalador ZIP",
                                    message: "La versión \(latest) todavía no ofrece un ZIP verificable para la instalación automática.")
                }
                return
            }
            status = .available(archive)
            if showAvailabilityNotice {
                notice = Notice(
                    title: "Actualización disponible",
                    message: "Música Local descargará e instalará la versión \(latest) y se reiniciará.",
                    archive: archive
                )
            }
        } else {
            status = .upToDate
            if reportResult {
                notice = Notice(title: "Música Local está al día", message: "Versión instalada \(installedText).")
            }
        }
    }

    func install(_ archive: UpdateInstaller.Archive) {
        guard !installing else { return }
        installing = true
        let destination = Bundle.main.bundleURL.resolvingSymlinksInPath()
        Task { await performInstall(archive, at: destination) }
    }

    private func performInstall(_ archive: UpdateInstaller.Archive, at destination: URL) async {
        do {
            try await Task.detached {
                try await UpdateInstaller.install(archive, at: destination)
            }.value
        } catch {
            notice = Notice(title: "No se pudo instalar la actualización", message: error.localizedDescription)
            installing = false
            return
        }
        status = .installed(archive.version)
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
            NSApp.terminate(nil)
        } catch {
            notice = Notice(title: "Actualización instalada",
                            message: "Cierra Música Local y vuelve a abrirla para iniciar la versión nueva.")
        }
        installing = false
    }

    private func report(_ message: String) {
        status = .failed(message)
        if reportResult {
            notice = Notice(title: "No se pudo buscar actualizaciones", message: message)
        }
    }
}
