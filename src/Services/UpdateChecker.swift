import Foundation
import Combine

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
}

struct GitHubMusicRelease: Decodable {
    struct Asset: Decodable {
        let browser_download_url: URL
        let state: String
    }

    let tag_name: String
    let name: String?
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var version: ReleaseVersion? {
        if let version = ReleaseVersion(tag_name) { return version }
        // La primera release usa la etiqueta de compatibilidad macOS12+.
        guard tag_name == "macOS12+", let name = name, name.hasPrefix("MusicaLocal ") else { return nil }
        return ReleaseVersion(String(name.dropFirst("MusicaLocal ".count)))
    }

    var releasePage: URL? {
        trustedURL(html_url, prefix: "/programmerbaez/MusicaLocal/releases/tag/")
    }

    var installer: URL? {
        let disks = assets.compactMap { asset -> URL? in
            guard asset.state == "uploaded", asset.browser_download_url.pathExtension.lowercased() == "dmg"
            else { return nil }
            return trustedURL(asset.browser_download_url, prefix: "/programmerbaez/MusicaLocal/releases/download/")
        }
        // Con varios instaladores, GitHub permite elegir la variante adecuada.
        return disks.count == 1 ? disks.first : nil
    }

    private func trustedURL(_ url: URL, prefix: String) -> URL? {
        guard url.scheme == "https", url.host == "github.com", url.user == nil,
              url.password == nil, url.port == nil, url.path.hasPrefix(prefix)
        else { return nil }
        return url
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var url: URL? = nil
        var action: String? = nil
    }

    @Published var notice: Notice?
    private var checkedAtLaunch = false
    private var checking = false
    private var reportResult = false

    func checkAutomatically() {
        guard !checkedAtLaunch else { return }
        checkedAtLaunch = true
        check(manual: false)
    }

    func check(manual: Bool = true) {
        reportResult = reportResult || manual
        guard !checking else { return }
        checking = true
        Task { await fetchLatestRelease() }
    }

    private func fetchLatestRelease() async {
        defer {
            checking = false
            reportResult = false
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
        guard let installedText = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let installed = ReleaseVersion(installedText),
              !release.draft, !release.prerelease,
              let latest = release.version, let page = release.releasePage else {
            report("No se pudo determinar la versión de la aplicación o de la publicación en GitHub.")
            return
        }
        if latest > installed {
            let installer = release.installer
            notice = Notice(
                title: "Actualización disponible",
                message: "Puedes instalar Música Local \(latest). Tu versión actual es \(installedText).",
                url: installer ?? page,
                action: installer == nil ? "Ver en GitHub" : "Descargar instalador"
            )
        } else if reportResult {
            notice = Notice(title: "Música Local está al día", message: "Versión instalada \(installedText).")
        }
    }

    private func report(_ message: String) {
        if reportResult {
            notice = Notice(title: "No se pudo buscar actualizaciones", message: message)
        }
    }
}
