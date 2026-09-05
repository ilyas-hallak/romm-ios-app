import Foundation

enum LocalROMDownloadError: LocalizedError {
    case insufficientStorage(required: Int64, available: Int64)
    case downloadFailed(String)
    case fileValidationFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientStorage(let required, let available):
            let requiredStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Insufficient storage: \(requiredStr) required, \(availableStr) available"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .fileValidationFailed(let message):
            return "File validation failed: \(message)"
        case .saveFailed(let message):
            return "Save failed: \(message)"
        }
    }
}

protocol PLocalROMDownloadService {
    /// Downloads ROM files to local device storage
    /// - Parameters:
    ///   - rom: The ROM to download
    ///   - files: The specific files to download
    ///   - progressHandler: Called with (downloaded bytes, total bytes, bytes per second)
    ///     during download. A non-positive total means the size is unknown.
    /// - Returns: The downloaded ROM metadata
    func downloadROM(
        rom: Rom,
        files: [RomFileInfo],
        progressHandler: @escaping (Int64, Int64, Double?) -> Void
    ) async throws -> DownloadedROM
}

class LocalROMDownloadService: PLocalROMDownloadService {

    private let apiClient: PRommAPIClient
    private let repository: PLocalROMRepository
    private let fileManager = FileManager.default

    init(
        apiClient: PRommAPIClient,
        repository: PLocalROMRepository = LocalROMRepository()
    ) {
        self.apiClient = apiClient
        self.repository = repository
    }

    func downloadROM(
        rom: Rom,
        files: [RomFileInfo],
        progressHandler: @escaping (Int64, Int64, Double?) -> Void
    ) async throws -> DownloadedROM {

        // 1. Calculate total size
        let totalSize = files.reduce(0) { $0 + $1.fileSizeBytes }

        // 2. Check available storage asynchronously to avoid blocking main thread
        let deviceManager = await MainActor.run { LocalDeviceManager.shared }
        await deviceManager.updateStorageInfoAsync()

        let hasEnoughStorage = await MainActor.run {
            deviceManager.hasEnoughStorage(for: totalSize)
        }

        guard hasEnoughStorage else {
            let availableStorage = await MainActor.run { deviceManager.availableStorageBytes }
            throw LocalROMDownloadError.insufficientStorage(
                required: totalSize,
                available: availableStorage
            )
        }

        // 3. Create ROM directory
        let platformName = rom.platform?.name ?? rom.platformSlug ?? ""
        let romDirectoryPath = LocalROMRepository.createROMDirectoryPath(
            platformName: platformName,
            romName: rom.name
        )

        let romDirectoryURL = repository.romsBaseURL.appendingPathComponent(romDirectoryPath)

        try fileManager.createDirectory(
            at: romDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // 4. Download each file
        var downloadedFiles: [DownloadedROMFile] = []
        var totalDownloadedBytes: Int64 = 0

        for (index, fileInfo) in files.enumerated() {
            print("📥 Downloading file \(index + 1)/\(files.count): \(fileInfo.fileName)")

            // Download file from server
            let localFileURL = romDirectoryURL.appendingPathComponent(fileInfo.fileName)

            // Metadata sizes of files not started yet — used to fill in the grand
            // total while the current file's real size is learned from URLSession.
            let remainingMetadata = files[(index + 1)...].reduce(0) { $0 + $1.fileSizeBytes }

            do {
                try await downloadFile(
                    fileName: fileInfo.fileName,
                    romId: rom.id,
                    to: localFileURL,
                    expectedSize: fileInfo.fileSizeBytes
                ) { downloadedBytes, fileTotalBytes, bytesPerSecond in
                    // `fileTotalBytes` is the announced size, or the metadata size
                    // passed in above when the server announced none. Clamped so an
                    // under-reported size cannot push the bar past 100%.
                    let currentTotalBytes = totalDownloadedBytes + downloadedBytes
                    let grandTotal: Int64
                    if fileTotalBytes > 0 {
                        grandTotal = max(
                            totalDownloadedBytes + fileTotalBytes + remainingMetadata,
                            currentTotalBytes
                        )
                    } else {
                        grandTotal = 0
                    }
                    Task { @MainActor in
                        progressHandler(currentTotalBytes, grandTotal, bytesPerSecond)
                    }
                }

                // Verify file was downloaded
                guard fileManager.fileExists(atPath: localFileURL.path) else {
                    throw LocalROMDownloadError.fileValidationFailed("File not found after download: \(fileInfo.fileName)")
                }

                // Get actual file size
                let attributes = try fileManager.attributesOfItem(atPath: localFileURL.path)
                let actualSize = attributes[FileAttributeKey.size] as? Int64 ?? 0

                // Validate file size
                if actualSize != fileInfo.fileSizeBytes {
                    print("⚠️ Warning: Downloaded file size mismatch for \(fileInfo.fileName)")
                    print("   Expected: \(fileInfo.fileSizeBytes), Got: \(actualSize)")
                    // Don't throw - some files might have compression differences
                }

                downloadedFiles.append(DownloadedROMFile(
                    fileName: fileInfo.fileName,
                    fileSizeBytes: actualSize,
                    md5Hash: nil
                ))

                totalDownloadedBytes += actualSize

            } catch {
                // Clean up on error
                try? fileManager.removeItem(at: romDirectoryURL)
                throw LocalROMDownloadError.downloadFailed(error.localizedDescription)
            }
        }

        // 5. Create DownloadedROM metadata
        let downloadedROM = DownloadedROM(
            id: rom.id,
            name: rom.name,
            platformName: platformName,
            platformSlug: rom.platformSlug ?? "",
            downloadedAt: Date(),
            totalSizeBytes: totalDownloadedBytes,
            localDirectory: romDirectoryPath,
            files: downloadedFiles,
            urlCover: rom.urlCover
        )

        // 6. Save metadata
        do {
            try repository.saveDownloadedROM(downloadedROM)
        } catch {
            // Clean up on error
            try? fileManager.removeItem(at: romDirectoryURL)
            throw LocalROMDownloadError.saveFailed(error.localizedDescription)
        }

        print("✅ Successfully downloaded ROM: \(rom.name)")
        print("   Files: \(downloadedFiles.count)")
        print("   Total size: \(ByteCountFormatter.string(fromByteCount: totalDownloadedBytes, countStyle: .file))")
        print("   Location: \(romDirectoryURL.path)")

        return downloadedROM
    }

    // MARK: - Private Helper Methods

    private func downloadFile(
        fileName: String,
        romId: Int,
        to destinationURL: URL,
        expectedSize: Int64,
        progressHandler: @escaping (Int64, Int64, Double?) -> Void
    ) async throws {
        let encodedFileName = encodePathComponent(fileName)
        // RomM 5.1 requires the filename in the path; RomM 5.0 used the bare
        // /content endpoint. Try the new format first and fall back to the
        // legacy one on 404 so downloads work against both server versions.
        let newPath = "api/roms/\(romId)/content/\(encodedFileName)"
        let legacyPath = "api/roms/\(romId)/content"

        let tempFileURL: URL
        do {
            tempFileURL = try await apiClient.downloadFile(
                path: newPath,
                expectedSize: expectedSize
            ) { downloadedBytes, totalBytes, bytesPerSecond in
                progressHandler(downloadedBytes, totalBytes, bytesPerSecond)
            }
        } catch let error {
            if case APIClientError.invalidResponse(404, _) = error {
                print("📥 /content/{filename} returned 404 — falling back to legacy /content (RomM 5.0)")
                do {
                    tempFileURL = try await apiClient.downloadFile(
                        path: legacyPath,
                        expectedSize: expectedSize
                    ) { downloadedBytes, totalBytes, bytesPerSecond in
                        progressHandler(downloadedBytes, totalBytes, bytesPerSecond)
                    }
                } catch {
                    throw LocalROMDownloadError.downloadFailed(error.localizedDescription)
                }
            } else {
                throw LocalROMDownloadError.downloadFailed(error.localizedDescription)
            }
        }

        // Move file to destination
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: tempFileURL, to: destinationURL)

        // Report final progress
        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let actualSize = attributes[.size] as? Int64 ?? 0
        if expectedSize > 0, actualSize <= 0 {
            throw LocalROMDownloadError.fileValidationFailed("Downloaded file is empty")
        }
        // No rate here: this file is done, the number would be stale.
        progressHandler(actualSize, actualSize, nil)
    }

    private func encodePathComponent(_ value: String) -> String {
        var allowedCharacterSet = CharacterSet.urlPathAllowed
        allowedCharacterSet.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? value
    }
}
