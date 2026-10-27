import Testing
import Foundation
@testable import romm

// The view model now serves a whole list rather than a single row, so the ROM
// it shares arrives with the tap. These tests pin that down, and the two
// outcomes a tap can have: files staged, or the not-found alert.

private final class StubGetROMShareFilesUseCase: PGetROMShareFilesUseCase {
    var filesToReturn: [URL] = []
    var tempDirectoryToReturn: URL?
    private(set) var sharedROMIds: [Int] = []

    func execute(rom: DownloadedROM) -> (files: [URL], tempDirectory: URL?) {
        sharedROMIds.append(rom.id)
        return (filesToReturn, tempDirectoryToReturn)
    }

    func execute(fileAt url: URL) -> (files: [URL], tempDirectory: URL?) {
        ([url], nil)
    }
}

private func makeDownloadedROM(id: Int, name: String = "Aardvark") -> DownloadedROM {
    DownloadedROM(
        id: id,
        name: name,
        platformName: "Atari 2600",
        platformSlug: "atari2600",
        downloadedAt: Date(timeIntervalSince1970: 0),
        totalSizeBytes: 33_000,
        localDirectory: "Atari 2600/\(name)",
        files: [DownloadedROMFile(id: UUID(), fileName: "\(name).bin", fileSizeBytes: 33_000, md5Hash: nil)],
        urlCover: nil
    )
}

@MainActor
struct ShareROMViewModelTests {

    @Test func prepareShareStagesTheFilesItWasGiven() {
        let stub = StubGetROMShareFilesUseCase()
        stub.filesToReturn = [URL(fileURLWithPath: "/tmp/ROMShare-1/Aardvark.bin")]
        stub.tempDirectoryToReturn = URL(fileURLWithPath: "/tmp/ROMShare-1")
        let vm = ShareROMViewModel(getShareFilesUseCase: stub)

        vm.prepareShare(rom: makeDownloadedROM(id: 42))

        #expect(vm.shareSheetItem?.urls.map(\.lastPathComponent) == ["Aardvark.bin"])
        #expect(vm.showFileNotFoundAlert == false)
        #expect(stub.sharedROMIds == [42])
    }

    @Test func prepareShareWithoutFilesAlertsInsteadOfPresenting() {
        let stub = StubGetROMShareFilesUseCase()
        let vm = ShareROMViewModel(getShareFilesUseCase: stub)

        vm.prepareShare(rom: makeDownloadedROM(id: 7))

        #expect(vm.shareSheetItem == nil)
        #expect(vm.showFileNotFoundAlert)
    }

    /// One instance serves every row, so a second tap has to replace the first
    /// staging rather than keep showing the previous ROM.
    @Test func secondTapRestagesForTheNewROM() {
        let stub = StubGetROMShareFilesUseCase()
        stub.filesToReturn = [URL(fileURLWithPath: "/tmp/ROMShare-1/Aardvark.bin")]
        let vm = ShareROMViewModel(getShareFilesUseCase: stub)

        vm.prepareShare(rom: makeDownloadedROM(id: 1, name: "Aardvark"))
        stub.filesToReturn = [URL(fileURLWithPath: "/tmp/ROMShare-2/Draconian.bin")]
        vm.prepareShare(rom: makeDownloadedROM(id: 2, name: "Draconian"))

        #expect(vm.shareSheetItem?.urls.map(\.lastPathComponent) == ["Draconian.bin"])
        #expect(stub.sharedROMIds == [1, 2])
    }
}
