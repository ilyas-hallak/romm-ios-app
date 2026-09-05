import Foundation

protocol PDownloadROMUseCase {
    /// Resolves the concrete files for a ROM from the server details and
    /// downloads them to local storage, reporting progress as
    /// (downloaded, total) bytes and the current rate.
    func execute(
        rom: Rom,
        progressHandler: @escaping (Int64, Int64, Double?) -> Void
    ) async throws -> DownloadedROM
}

/// Owns the "resolve which files a ROM consists of, then download them"
/// orchestration so the download queue stays a thin state coordinator and the
/// data access lives in the domain layer.
final class DownloadROMUseCase: PDownloadROMUseCase {

    private let apiClient: PRommAPIClient
    private let downloadService: PLocalROMDownloadService

    init(
        apiClient: PRommAPIClient,
        downloadService: PLocalROMDownloadService? = nil
    ) {
        self.apiClient = apiClient
        self.downloadService = downloadService ?? LocalROMDownloadService(apiClient: apiClient)
    }

    func execute(
        rom: Rom,
        progressHandler: @escaping (Int64, Int64, Double?) -> Void
    ) async throws -> DownloadedROM {
        let files = try await resolveFiles(for: rom)
        return try await downloadService.downloadROM(
            rom: rom,
            files: files,
            progressHandler: progressHandler
        )
    }

    /// Builds the file list from the server ROM details, falling back to a
    /// single file derived from the ROM itself when the details carry none.
    private func resolveFiles(for rom: Rom) async throws -> [RomFileInfo] {
        let details = try await apiClient.getRomDetails(id: rom.id)
        var files: [RomFileInfo] = []
        if !details.fsName.isEmpty {
            files.append(RomFileInfo(
                id: details.fsName,
                fileName: details.fsName,
                fileSizeBytes: Int64(details.fsSizeBytes),
                fileExtension: (details.fsName as NSString).pathExtension
            ))
        }
        for supplementary in details.files
        where supplementary.fileName != details.fsName && !supplementary.fileName.isEmpty {
            files.append(RomFileInfo(from: supplementary))
        }
        if files.isEmpty {
            let fallbackName = rom.fileName ?? "\(rom.name).rom"
            files = [RomFileInfo(
                id: fallbackName,
                fileName: fallbackName,
                fileSizeBytes: Int64(rom.sizeBytes ?? 0),
                fileExtension: (fallbackName as NSString).pathExtension
            )]
        }
        return files
    }
}
