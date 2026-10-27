import Foundation
import Observation

/// Collects the files behind a downloaded ROM so the list can hand them to the
/// share sheet. One instance serves the whole list: the ROM arrives with the tap
/// rather than at init, because the view that presents the sheet has to outlive
/// the row that started it.
@Observable
@MainActor
final class ShareROMViewModel {
    var shareSheetItem: ShareSheetItem?
    var showFileNotFoundAlert = false

    private let getShareFilesUseCase: PGetROMShareFilesUseCase
    private var temporaryShareDirectory: URL?

    init(getShareFilesUseCase: PGetROMShareFilesUseCase) {
        self.getShareFilesUseCase = getShareFilesUseCase
    }

    func prepareShare(rom: DownloadedROM) {
        let (files, tempDir) = getShareFilesUseCase.execute(rom: rom)
        if files.isEmpty {
            showFileNotFoundAlert = true
        } else {
            temporaryShareDirectory = tempDir
            shareSheetItem = ShareSheetItem(urls: files)
        }
    }

    func cleanupTemporaryFiles() {
        guard let tempDir = temporaryShareDirectory else { return }
        try? FileManager.default.removeItem(at: tempDir)
        temporaryShareDirectory = nil
        shareSheetItem = nil
    }
}

struct ShareSheetItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}
