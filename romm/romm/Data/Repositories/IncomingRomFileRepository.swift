//
//  IncomingRomFileRepository.swift
//  romm
//

import Foundation

nonisolated final class IncomingRomFileRepository: PIncomingRomFileRepository {
    private var fileManager: FileManager { .default }
    private let rootDirectory: URL
    private let inboxDirectory: URL

    init(
        rootDirectory: URL = {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return base.appendingPathComponent("PendingUploads", isDirectory: true)
        }(),
        inboxDirectory: URL = {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return base.appendingPathComponent("Inbox", isDirectory: true)
        }()
    ) {
        self.rootDirectory = rootDirectory
        self.inboxDirectory = inboxDirectory
    }

    func stage(url: URL) throws -> StagedRomFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let jobId = UUID()
        let jobFolder = rootDirectory.appendingPathComponent(jobId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: jobFolder, withIntermediateDirectories: true)

        do {
            let fileName = url.lastPathComponent
            let destination = jobFolder.appendingPathComponent(fileName)

            // "Open In" with LSSupportsOpeningDocumentsInPlace = false already
            // copied the file into our own Inbox, so moving it here avoids a
            // second copy of what can be a multi-gigabyte disc image, and
            // leaves no orphan behind in the Inbox. Anything else (a
            // security-scoped URL from a file picker) is not ours to move.
            if isInInbox(url) {
                try fileManager.moveItem(at: url, to: destination)
            } else {
                try fileManager.copyItem(at: url, to: destination)
            }

            let attributes = try fileManager.attributesOfItem(atPath: destination.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            guard fileSize > 0 else {
                throw RomUploadError.emptyFile
            }

            log("Staged incoming ROM file \(fileName) (\(fileSize) bytes) as job \(jobId)")
            return StagedRomFile(
                id: jobId,
                fileName: fileName,
                fileSize: fileSize,
                fileURL: destination,
                relativePath: "\(jobId.uuidString)/\(fileName)"
            )
        } catch {
            try? fileManager.removeItem(at: jobFolder)
            throw error
        }
    }

    func removeStagedFile(relativePath: String) {
        guard let jobId = relativePath.split(separator: "/").first else { return }
        let jobFolder = rootDirectory.appendingPathComponent(String(jobId), isDirectory: true)
        try? fileManager.removeItem(at: jobFolder)
    }

    /// `relativePath` is `<jobId>/<fileName>`, as produced by `stage(url:)`.
    func resolve(relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath)
    }

    private func log(_ message: String) {
        Task { @MainActor in
            Logger.data.info(message)
        }
    }

    /// Compares standardized, symlink-resolved paths, since the Inbox URL
    /// handed in can be `/var/...` while `FileManager` reports `/private/var/...`
    /// (or vice versa) for the same file.
    private func isInInbox(_ url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedInbox = inboxDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedURL.hasPrefix(resolvedInbox + "/")
    }
}
