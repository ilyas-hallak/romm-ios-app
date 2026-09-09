//
//  ROMDownloadFinalizer.swift
//  romm
//

import Foundation

/// The directory a ROM download writes into, plus the bookkeeping cleanup needs.
struct ROMDownloadDestination {
    /// Path relative to the ROM repository's base directory, e.g. "Game Boy/Pokemon Red".
    let relativePath: String
    /// Absolute directory the transfer writes its files into.
    let directoryURL: URL
    /// True when `prepare` created the directory, false when it was already there.
    let didCreateDirectory: Bool
    /// The file names this download is responsible for. Cleanup uses them to tell
    /// its own files apart from files that were in the directory beforehand.
    let ownedFileNames: [String]
}

/// Reports how much room the device volume has left.
///
/// The real implementation talks to a main-actor singleton, so this indirection
/// exists to keep the storage check testable.
protocol PDeviceStorageProbe {
    /// Refreshes the volume figures, then reports whether `bytes` additional bytes
    /// fit, together with the free bytes that decision was made on.
    func checkStorage(forAdditionalBytes bytes: Int64) async -> (fits: Bool, availableBytes: Int64)
}

/// Storage probe backed by `LocalDeviceManager`, which keeps the safety margin
/// applied to every download target.
struct LocalDeviceStorageProbe: PDeviceStorageProbe {
    func checkStorage(forAdditionalBytes bytes: Int64) async -> (fits: Bool, availableBytes: Int64) {
        let deviceManager = await MainActor.run { LocalDeviceManager.shared }
        await deviceManager.updateStorageInfoAsync()
        return await MainActor.run {
            (
                fits: deviceManager.hasEnoughStorage(for: bytes),
                availableBytes: deviceManager.availableStorageBytes
            )
        }
    }
}

/// Everything a ROM download needs around the actual byte transfer: the storage
/// check and target directory up front, size validation and metadata afterwards,
/// and cleanup when something goes wrong.
///
/// The transfer itself is deliberately not part of this, so a foreground
/// `URLSession` download and a background one can share the same preparation
/// and completion steps.
protocol PROMDownloadFinalizer {
    /// Checks storage and creates the target directory for a ROM.
    /// - Parameters:
    ///   - rom: The ROM the files belong to
    ///   - files: The files that are about to be transferred
    ///   - reservedBytes: Bytes already promised to transfers that are open but
    ///     not written yet. Callers that keep several downloads in flight pass the
    ///     sum of their outstanding sizes here so the volume is checked against the
    ///     whole commitment, not just this ROM. Pass 0 for a single download.
    /// - Returns: The prepared destination
    func prepare(
        rom: Rom,
        files: [RomFileInfo],
        reservedBytes: Int64
    ) async throws -> ROMDownloadDestination

    /// Validates a single transferred file and returns its metadata entry.
    ///
    /// The returned size is the size on disk, not the size the server announced.
    func validateTransferredFile(
        named fileName: String,
        expectedSize: Int64,
        in destination: ROMDownloadDestination
    ) throws -> DownloadedROMFile

    /// Validates every transferred file and writes the ROM metadata.
    /// - Returns: The stored ROM metadata
    func finish(
        rom: Rom,
        files: [RomFileInfo],
        destination: ROMDownloadDestination
    ) throws -> DownloadedROM

    /// Writes the ROM metadata for files that have already been validated.
    ///
    /// For callers that validate every file as it lands, so no file is measured
    /// and no mismatch logged a second time.
    /// - Returns: The stored ROM metadata
    func writeMetadata(
        rom: Rom,
        destination: ROMDownloadDestination,
        validatedFiles: [DownloadedROMFile]
    ) throws -> DownloadedROM

    /// Removes what this download put on disk.
    ///
    /// The whole directory goes only when `prepare` created it. A directory that
    /// was already there can hold files of an earlier download, so in that case
    /// only the file names the destination owns are removed and the directory
    /// stays. Deleting it wholesale would take foreign files with it.
    func cleanUp(_ destination: ROMDownloadDestination)
}

class ROMDownloadFinalizer: PROMDownloadFinalizer {

    private let repository: PLocalROMRepository
    private let storageProbe: PDeviceStorageProbe
    private let fileManager = FileManager.default
    private let logger = Logger.data

    init(
        repository: PLocalROMRepository = LocalROMRepository(),
        storageProbe: PDeviceStorageProbe = LocalDeviceStorageProbe()
    ) {
        self.repository = repository
        self.storageProbe = storageProbe
    }

    func prepare(
        rom: Rom,
        files: [RomFileInfo],
        reservedBytes: Int64
    ) async throws -> ROMDownloadDestination {
        let requiredBytes = files.reduce(reservedBytes) { $0 + $1.fileSizeBytes }

        let storage = await storageProbe.checkStorage(forAdditionalBytes: requiredBytes)
        guard storage.fits else {
            throw LocalROMDownloadError.insufficientStorage(
                required: requiredBytes,
                available: storage.availableBytes
            )
        }

        let relativePath = LocalROMRepository.createROMDirectoryPath(
            platformName: Self.platformName(of: rom),
            romName: rom.name
        )
        let directoryURL = repository.romsBaseURL.appendingPathComponent(relativePath)
        let didCreateDirectory = !fileManager.fileExists(atPath: directoryURL.path)

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return ROMDownloadDestination(
            relativePath: relativePath,
            directoryURL: directoryURL,
            didCreateDirectory: didCreateDirectory,
            ownedFileNames: files.map(\.fileName)
        )
    }

    func validateTransferredFile(
        named fileName: String,
        expectedSize: Int64,
        in destination: ROMDownloadDestination
    ) throws -> DownloadedROMFile {
        let fileURL = destination.directoryURL.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw LocalROMDownloadError.fileValidationFailed("File not found after download: \(fileName)")
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let actualSize = attributes[FileAttributeKey.size] as? Int64 ?? 0

        // A file that stayed empty although the server announced content is a
        // torso and cannot be used.
        if expectedSize > 0, actualSize <= 0 {
            throw LocalROMDownloadError.fileValidationFailed("Downloaded file is empty")
        }

        // A size that merely differs from the metadata is not an error: servers
        // report sizes that can legitimately deviate, for example through
        // compression. The size on disk wins and is what gets stored.
        if actualSize != expectedSize {
            logger.warning("Downloaded file size mismatch for \(fileName), expected \(expectedSize), got \(actualSize)")
        }

        return DownloadedROMFile(
            fileName: fileName,
            fileSizeBytes: actualSize,
            md5Hash: nil
        )
    }

    func finish(
        rom: Rom,
        files: [RomFileInfo],
        destination: ROMDownloadDestination
    ) throws -> DownloadedROM {
        var downloadedFiles: [DownloadedROMFile] = []
        for file in files {
            downloadedFiles.append(
                try validateTransferredFile(
                    named: file.fileName,
                    expectedSize: file.fileSizeBytes,
                    in: destination
                )
            )
        }

        return try writeMetadata(
            rom: rom,
            destination: destination,
            validatedFiles: downloadedFiles
        )
    }

    func writeMetadata(
        rom: Rom,
        destination: ROMDownloadDestination,
        validatedFiles: [DownloadedROMFile]
    ) throws -> DownloadedROM {
        let downloadedROM = DownloadedROM(
            id: rom.id,
            name: rom.name,
            platformName: Self.platformName(of: rom),
            platformSlug: rom.platformSlug ?? "",
            downloadedAt: Date(),
            totalSizeBytes: validatedFiles.reduce(0) { $0 + $1.fileSizeBytes },
            localDirectory: destination.relativePath,
            files: validatedFiles,
            urlCover: rom.urlCover
        )

        do {
            try repository.saveDownloadedROM(downloadedROM)
        } catch {
            throw LocalROMDownloadError.saveFailed(error.localizedDescription)
        }

        return downloadedROM
    }

    func cleanUp(_ destination: ROMDownloadDestination) {
        if destination.didCreateDirectory {
            try? fileManager.removeItem(at: destination.directoryURL)
            return
        }

        for fileName in destination.ownedFileNames {
            let fileURL = destination.directoryURL.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Private Helper Methods

    /// The platform name the ROM directory is filed under. The slug stands in
    /// when the platform was not loaded with the ROM.
    private static func platformName(of rom: Rom) -> String {
        rom.platform?.name ?? rom.platformSlug ?? ""
    }
}
