import CryptoKit
import Darwin
import Foundation

enum UpdateInstaller {
    struct Archive {
        let url: URL
        let sha256: String
        let version: ReleaseVersion
    }

    enum InstallError: LocalizedError {
        case download, checksum, package, compatibility, signature, destination

        var errorDescription: String? {
            switch self {
            case .download: return "No se pudo descargar el archivo ZIP desde GitHub."
            case .checksum: return "El contenido del ZIP no coincide con la huella SHA-256 publicada en GitHub."
            case .package: return "El ZIP no contiene el paquete de Música Local y la versión esperados."
            case .compatibility: return "La nueva versión requiere otro procesador o una versión más reciente de macOS."
            case .signature: return "No se pudo verificar la firma del paquete descargado."
            case .destination: return "No se pudo reemplazar la aplicación en su ubicación actual. Muévela a una carpeta con permiso de escritura y vuelve a intentarlo."
            }
        }
    }

    static func install(_ archive: Archive, at destination: URL) async throws {
        let files = FileManager.default
        let parent = destination.deletingLastPathComponent()
        guard destination.pathExtension == "app",
              files.isWritableFile(atPath: parent.path),
              files.fileExists(atPath: destination.path) else { throw InstallError.destination }

        let (download, response) = try await URLSession.shared.download(from: archive.url)
        defer { try? files.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.url?.scheme == "https" else { throw InstallError.download }
        try verifyChecksum(of: download, expected: archive.sha256)
        try installVerifiedArchive(download, version: archive.version, at: destination)
    }

    static func verifyChecksum(of file: URL, expected: String) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var hash = SHA256()
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw InstallError.checksum }
    }

    static func installVerifiedArchive(_ zip: URL, version: ReleaseVersion, at destination: URL) throws {
        let files = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".musicalocal-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: false,
                                      attributes: [.posixPermissions: 0o700])
        } catch {
            throw InstallError.destination
        }
        defer { try? files.removeItem(at: staging) }

        guard try run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path]) else { throw InstallError.package }
        let candidate = staging.appendingPathComponent("MusicaLocal.app", isDirectory: true)
        guard let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink == false,
              let bundle = Bundle(url: candidate), bundle.bundleIdentifier == "com.local.musicalocal",
              let versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              ReleaseVersion(versionText) == version else { throw InstallError.package }

        #if arch(arm64)
        let requiredCPU = CPU_TYPE_ARM64
        #else
        let requiredCPU = CPU_TYPE_X86_64
        #endif
        let currentOS = ProcessInfo.processInfo.operatingSystemVersion
        let installedOS = ReleaseVersion("\(currentOS.majorVersion).\(currentOS.minorVersion).\(currentOS.patchVersion)")!
        guard let minimumText = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
              let minimumOS = ReleaseVersion(minimumText), minimumOS <= installedOS,
              bundle.executableArchitectures?.contains(NSNumber(value: requiredCPU)) == true else {
            throw InstallError.compatibility
        }
        guard try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path]) else {
            throw InstallError.signature
        }

        // El intercambio atómico conserva el paquete instalado si falla la operación.
        let result = candidate.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                renamex_np(source, target, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw InstallError.destination }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
