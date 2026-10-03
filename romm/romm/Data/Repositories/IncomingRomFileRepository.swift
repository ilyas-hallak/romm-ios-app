//
//  IncomingRomFileRepository.swift
//  romm
//

import Foundation

final class IncomingRomFileRepository: PIncomingRomFileRepository {
    private let logger = Logger.data
    private let fileManager = FileManager.default

    private var pendingUploadsRoot: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PendingUploads", isDirectory: true)
    }

    func stage(url: URL) throws -> StagedRomFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let jobId = UUID()
        let jobFolder = pendingUploadsRoot.appendingPathComponent(jobId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: jobFolder, withIntermediateDirectories: true)

        let fileName = url.lastPathComponent
        let destination = jobFolder.appendingPathComponent(fileName)
        try fileManager.copyItem(at: url, to: destination)

        let attributes = try fileManager.attributesOfItem(atPath: destination.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        logger.info("Staged incoming ROM file \(fileName) (\(fileSize) bytes) as job \(jobId)")
        return StagedRomFile(
            id: jobId,
            fileName: fileName,
            fileSize: fileSize,
            fileURL: destination,
            relativePath: "\(jobId.uuidString)/\(fileName)"
        )
    }

    func removeStagedFile(_ file: StagedRomFile) {
        let jobFolder = file.fileURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: jobFolder)
    }

    /// `relativePath` is `<jobId>/<fileName>`, as produced by `stage(url:)`.
    func resolve(relativePath: String) -> URL {
        pendingUploadsRoot.appendingPathComponent(relativePath)
    }
}
