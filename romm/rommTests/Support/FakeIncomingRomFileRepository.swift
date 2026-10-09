//
//  FakeIncomingRomFileRepository.swift
//  rommTests
//
//  Stages files to a throwaway directory on disk, since real callers (the
//  upload queue, the incoming URL router) read the staged file's actual bytes.
//

import Foundation
@testable import romm

final class FakeIncomingRomFileRepository: PIncomingRomFileRepository, @unchecked Sendable {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rom-upload-tests-\(UUID().uuidString)")
    private(set) var removedRelativePaths: [String] = []
    var stageError: Error?

    init() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Writes `contents` under a fresh job id and returns the staged file,
    /// mirroring what `stage(url:)` would have produced.
    func seed(fileName: String, contents: Data) -> StagedRomFile {
        let jobId = UUID()
        let jobDirectory = root.appendingPathComponent(jobId.uuidString)
        try? FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        let fileURL = jobDirectory.appendingPathComponent(fileName)
        try? contents.write(to: fileURL)
        return StagedRomFile(
            id: jobId,
            fileName: fileName,
            fileSize: Int64(contents.count),
            fileURL: fileURL,
            relativePath: "\(jobId.uuidString)/\(fileName)"
        )
    }

    func stage(url: URL) throws -> StagedRomFile {
        if let stageError { throw stageError }
        return seed(fileName: url.lastPathComponent, contents: try Data(contentsOf: url))
    }

    func removeStagedFile(relativePath: String) {
        removedRelativePaths.append(relativePath)
        guard let jobId = relativePath.split(separator: "/").first else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(String(jobId)))
    }

    func resolve(relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }
}
