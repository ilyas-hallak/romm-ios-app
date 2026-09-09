import Foundation

/// The files a ROM is made of, as the queue needs them before it can start a
/// single transfer.
///
/// Its own seam because this is the one thing the queue has to ask the server
/// for, while everything else it does is local. A fake in its place lets the
/// whole queue be driven without a network.
protocol PROMFileListProvider {
    func files(for rom: Rom) async throws -> [RomFileInfo]
}

/// Works the file list out from the server ROM details: the ROM's own file
/// first, then the supplementary ones, and a name derived from the ROM itself
/// when the details carry none.
final class ROMDetailsFileListProvider: PROMFileListProvider {

    private let apiClient: PRommAPIClient

    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }

    func files(for rom: Rom) async throws -> [RomFileInfo] {
        let details = try await apiClient.getRomDetails(id: rom.id)
        var files = primaryFile(of: details).map { [$0] } ?? []
        files += supplementaryFiles(of: details)
        return files.isEmpty ? [fallbackFile(for: rom)] : files
    }

    /// The ROM's own file, or nil when the details name none.
    private func primaryFile(of details: DetailedRomSchema) -> RomFileInfo? {
        guard !details.fsName.isEmpty else { return nil }
        return RomFileInfo(
            id: details.fsName,
            fileName: details.fsName,
            fileSizeBytes: Int64(details.fsSizeBytes),
            fileExtension: (details.fsName as NSString).pathExtension
        )
    }

    /// Everything the details list besides the ROM's own file.
    private func supplementaryFiles(of details: DetailedRomSchema) -> [RomFileInfo] {
        details.files
            .filter { $0.fileName != details.fsName && !$0.fileName.isEmpty }
            .map(RomFileInfo.init(from:))
    }

    /// Stands in when the details carry no usable file at all.
    private func fallbackFile(for rom: Rom) -> RomFileInfo {
        let name = rom.fileName ?? "\(rom.name).rom"
        return RomFileInfo(
            id: name,
            fileName: name,
            fileSizeBytes: Int64(rom.sizeBytes ?? 0),
            fileExtension: (name as NSString).pathExtension
        )
    }
}
