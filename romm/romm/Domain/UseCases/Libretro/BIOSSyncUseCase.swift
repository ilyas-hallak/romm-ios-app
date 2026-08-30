import Foundation

protocol PBIOSSyncUseCase {
    func systemDirectory() -> URL
    func loadStatuses(for core: LibretroCore) async throws -> [BIOSFileStatus]
    func download(status: BIOSFileStatus, into systemDir: URL) async throws
    /// Gibt fehlende, harte Anforderungen zurück (für Launch-Warnung).
    func missingMandatory(for core: LibretroCore) async -> [LibretroBIOSFile]
}

final class BIOSSyncUseCase: PBIOSSyncUseCase {
    private let apiClient: PRommAPIClient
    private let fileSystem: PFileSystemService
    private let logger = Logger.viewModel

    init(apiClient: PRommAPIClient, fileSystem: PFileSystemService) {
        self.apiClient = apiClient
        self.fileSystem = fileSystem
    }

    func systemDirectory() -> URL {
        let dir = fileSystem.documentsDirectory().appendingPathComponent("LibretroSystem", isDirectory: true)
        try? fileSystem.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func loadStatuses(for core: LibretroCore) async throws -> [BIOSFileStatus] {
        let required = LibretroBIOSRequirement.files(for: core)
        let serverFirmware = try await loadServerFirmware(for: core)
        let dir = systemDirectory()

        return required.map { req in
            let localURL = req.localURL(in: dir)
            let local: BIOSFileStatus.LocalState
            if fileSystem.fileExists(at: localURL) {
                let md5 = BIOSFileHashing.md5(of: localURL) ?? ""
                let size = BIOSFileHashing.fileSize(of: localURL) ?? 0
                local = .present(md5: md5, sizeBytes: size)
            } else {
                local = .missing
            }

            let server: BIOSFileStatus.ServerState
            if let match = serverFirmware.first(where: {
                $0.fileName.caseInsensitiveCompare(req.fileName) == .orderedSame
            }) {
                server = .available(
                    firmwareId: match.id,
                    sizeBytes: match.fileSizeBytes,
                    md5: match.md5Hash,
                    isVerified: match.isVerified
                )
            } else if serverFirmware.isEmpty {
                server = .unknown
            } else {
                server = .missing
            }

            return BIOSFileStatus(requirement: req, local: local, server: server)
        }
    }

    func download(status: BIOSFileStatus, into systemDir: URL) async throws {
        guard case .available(let id, _, _, _) = status.server else {
            throw NSError(domain: "BIOSSync", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "The server does not have \(status.requirement.fileName).")
            ])
        }
        let data = try await apiClient.downloadFirmwareContent(id: id, fileName: status.requirement.fileName)
        let target = status.requirement.localURL(in: systemDir)
        // Ohne das Unterverzeichnis (z. B. dc/) scheitert der Schreibvorgang.
        try fileSystem.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileSystem.write(data, to: target)
        logger.info("BIOS gespeichert: \(target.path) (\(data.count) bytes)")
    }

    func missingMandatory(for core: LibretroCore) async -> [LibretroBIOSFile] {
        let dir = systemDirectory()
        let files = LibretroBIOSRequirement.files(for: core)
        if let anyOf = LibretroBIOSRequirement.atLeastOneOfFileNames(for: core) {
            let hasAny = files.contains { req in
                anyOf.contains(req.fileName) && fileSystem.fileExists(at: req.localURL(in: dir))
            }
            if hasAny { return [] }
        }
        return files.filter { $0.required }.filter { req in
            !fileSystem.fileExists(at: req.localURL(in: dir))
        }
    }

    private func loadServerFirmware(for core: LibretroCore) async throws -> [FirmwareSchema] {
        let platforms = try await apiClient.getPlatforms()
        let slugs = Set(LibretroBIOSRequirement.platformSlugs(for: core).map { $0.lowercased() })
        let matches = platforms.filter { slugs.contains($0.slug.lowercased()) }
        if matches.isEmpty { return [] }
        var firmware: [FirmwareSchema] = []
        for platform in matches {
            if let embedded = platform.firmware, !embedded.isEmpty {
                firmware.append(contentsOf: embedded)
            } else {
                let fetched = try await apiClient.getPlatformFirmware(platformId: platform.id)
                firmware.append(contentsOf: fetched)
            }
        }
        return firmware
    }
}
