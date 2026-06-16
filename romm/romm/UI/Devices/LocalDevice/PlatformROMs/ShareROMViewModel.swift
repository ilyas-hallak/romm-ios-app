import Foundation
import Observation

@Observable
@MainActor
final class ShareROMViewModel {
    var shareSheetItem: ShareSheetItem?
    var showFileNotFoundAlert = false

    private let rom: DownloadedROM
    private let getShareFilesUseCase: PGetROMShareFilesUseCase
    private var temporaryShareDirectory: URL?

    init(rom: DownloadedROM, getShareFilesUseCase: PGetROMShareFilesUseCase) {
        self.rom = rom
        self.getShareFilesUseCase = getShareFilesUseCase
    }

    func prepareShare() {
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
