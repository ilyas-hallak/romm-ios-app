import SwiftUI

struct ShareSwipeButton: View {
    let rom: DownloadedROM
    @State private var shareSheetItem: ShareSheetItem?
    @State private var showFileNotFoundAlert = false
    @State private var temporaryShareDirectory: URL?

    var body: some View {
        Button {
            let (files, tempDir) = getROMFiles()
            if files.isEmpty {
                showFileNotFoundAlert = true
            } else {
                temporaryShareDirectory = tempDir
                shareSheetItem = ShareSheetItem(urls: files)
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
        .sheet(item: $shareSheetItem, onDismiss: cleanupTemporaryFiles) { item in
            ShareSheet(activityItems: item.urls)
        }
        .alert("Files Not Found", isPresented: $showFileNotFoundAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The ROM files could not be found on this device. They may have been deleted or moved.")
        }
    }

    // MARK: - File Sharing Logic

    private func getROMFiles() -> (files: [URL], tempDirectory: URL?) {
        let romsBaseURL = LocalROMRepository().romsBaseURL
        let fileManager = FileManager.default
        let shareDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ROMShare-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: shareDirectory, withIntermediateDirectories: true)

        var romDirectoryURL = romsBaseURL.appendingPathComponent(rom.localDirectory)
        if !fileManager.fileExists(atPath: romDirectoryURL.path) {
            guard let actualPath = findActualROMPath(romsBaseURL: romsBaseURL, romName: rom.name, fileManager: fileManager) else {
                return ([], nil)
            }
            romDirectoryURL = actualPath
        }

        var urls: [URL] = []
        for file in rom.files {
            let src = romDirectoryURL.appendingPathComponent(file.fileName)
            let dst = shareDirectory.appendingPathComponent(file.fileName)
            guard fileManager.fileExists(atPath: src.path) else { continue }
            do {
                try fileManager.copyItem(at: src, to: dst)
                try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dst.path)
                urls.append(dst)
            } catch {}
        }

        return (urls, urls.isEmpty ? nil : shareDirectory)
    }

    private func findActualROMPath(romsBaseURL: URL, romName: String, fileManager: FileManager) -> URL? {
        guard let platformDirs = try? fileManager.contentsOfDirectory(
            at: romsBaseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for platformDir in platformDirs {
            let romDir = platformDir.appendingPathComponent(romName)
            if fileManager.fileExists(atPath: romDir.path) { return romDir }
        }
        return nil
    }

    private func cleanupTemporaryFiles() {
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
