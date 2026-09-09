import Foundation

/// One file a ROM is made of, as everything that moves ROMs works with it: the
/// download queue, the transfers themselves, the finalizer that files them away
/// and the SFTP upload screen.
///
/// Deliberately thinner than the server schema it is usually built from. All a
/// transfer needs is a name, an announced size and something stable to key on,
/// and keeping it at that lets the download stack be driven in tests without a
/// server response to hand.
///
/// Nonisolated like the rest of the download models, because it travels through
/// the job store and the finalizer, neither of which is on the main actor.
nonisolated struct RomFileInfo: Identifiable, Hashable {
    let id: String
    let fileName: String
    let fileSizeBytes: Int64
    let fileExtension: String

    init(from romFile: RomFileSchema) {
        self.id = romFile.fileName
        self.fileName = romFile.fileName
        self.fileSizeBytes = Int64(romFile.fileSizeBytes)
        self.fileExtension = (romFile.fileName as NSString).pathExtension
    }

    init(id: String, fileName: String, fileSizeBytes: Int64, fileExtension: String) {
        self.id = id
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.fileExtension = fileExtension
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}
