import Testing
import Foundation
@testable import romm

/// Keeps the ROM base directory inside the test's temporary folder and records
/// what the finalizer asked it to store.
private final class FakeLocalROMs: PLocalROMRepository, @unchecked Sendable {
    let romsBaseURL: URL
    var saved: [DownloadedROM] = []
    var saveError: Error?

    init(romsBaseURL: URL) {
        self.romsBaseURL = romsBaseURL
    }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { saved }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { saved.first { $0.id == id } }

    func saveDownloadedROM(_ rom: DownloadedROM) throws {
        if let saveError { throw saveError }
        saved.append(rom)
    }

    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { saved.count }
}

/// Stands in for the device volume. It compares plainly, the safety margin the
/// real device applies is not what these tests are about.
private final class FakeStorageProbe: PDeviceStorageProbe, @unchecked Sendable {
    var availableBytes: Int64
    var requestedBytes: Int64?

    init(availableBytes: Int64) {
        self.availableBytes = availableBytes
    }

    func checkStorage(forAdditionalBytes bytes: Int64) async -> (fits: Bool, availableBytes: Int64) {
        requestedBytes = bytes
        return (fits: availableBytes >= bytes, availableBytes: availableBytes)
    }
}

struct ROMDownloadFinalizerTests {

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ROMDownloadFinalizer-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func remove(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func rom() -> Rom {
        Rom(id: 7, name: "Pokemon Red", platformId: 1, urlCover: nil, platformSlug: "gb")
    }

    private func file(_ name: String, size: Int64) -> RomFileInfo {
        RomFileInfo(
            id: name,
            fileName: name,
            fileSizeBytes: size,
            fileExtension: (name as NSString).pathExtension
        )
    }

    private func write(_ name: String, bytes: Int, in directory: URL) {
        let url = directory.appendingPathComponent(name)
        try? Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    @Test func storesMetadataWithTheSizesFoundOnDisk() async throws {
        let root = makeRoot()
        defer { remove(root) }
        let repository = FakeLocalROMs(romsBaseURL: root)
        let finalizer = ROMDownloadFinalizer(
            repository: repository,
            storageProbe: FakeStorageProbe(availableBytes: 1_000)
        )
        let files = [file("red.gb", size: 10), file("red.sav", size: 20)]

        let destination = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 0)
        write("red.gb", bytes: 10, in: destination.directoryURL)
        write("red.sav", bytes: 20, in: destination.directoryURL)

        let stored = try finalizer.finish(rom: rom(), files: files, destination: destination)

        #expect(destination.relativePath == "gb/Pokemon Red")
        // Compared as paths, not URLs: `appendingPathComponent` consults the file
        // system and appends a trailing slash once the directory exists.
        #expect(destination.directoryURL.path == root.appendingPathComponent("gb/Pokemon Red").path)
        #expect(repository.saved.count == 1)
        #expect(stored.localDirectory == "gb/Pokemon Red")
        #expect(stored.files.map(\.fileName) == ["red.gb", "red.sav"])
        #expect(stored.files.map(\.fileSizeBytes) == [10, 20])
        #expect(stored.totalSizeBytes == 30)
    }

    /// Announced and actual sizes can differ legitimately, so the size on disk is
    /// stored and the transfer counts as finished.
    @Test func doesNotThrowOnASizeMismatch() async throws {
        let root = makeRoot()
        defer { remove(root) }
        let repository = FakeLocalROMs(romsBaseURL: root)
        let finalizer = ROMDownloadFinalizer(
            repository: repository,
            storageProbe: FakeStorageProbe(availableBytes: 1_000)
        )
        let files = [file("red.gb", size: 999)]

        let destination = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 0)
        write("red.gb", bytes: 5, in: destination.directoryURL)

        let stored = try finalizer.finish(rom: rom(), files: files, destination: destination)

        #expect(stored.files.map(\.fileSizeBytes) == [5])
        #expect(stored.totalSizeBytes == 5)
    }

    @Test func throwsWhenAFileIsMissing() async throws {
        let root = makeRoot()
        defer { remove(root) }
        let finalizer = ROMDownloadFinalizer(
            repository: FakeLocalROMs(romsBaseURL: root),
            storageProbe: FakeStorageProbe(availableBytes: 1_000)
        )
        let files = [file("red.gb", size: 10)]

        let destination = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 0)

        #expect(throws: LocalROMDownloadError.self) {
            try finalizer.finish(rom: rom(), files: files, destination: destination)
        }
    }

    @Test func throwsWhenAFileIsEmptyButContentWasAnnounced() async throws {
        let root = makeRoot()
        defer { remove(root) }
        let finalizer = ROMDownloadFinalizer(
            repository: FakeLocalROMs(romsBaseURL: root),
            storageProbe: FakeStorageProbe(availableBytes: 1_000)
        )
        let files = [file("red.gb", size: 10)]

        let destination = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 0)
        write("red.gb", bytes: 0, in: destination.directoryURL)

        #expect(throws: LocalROMDownloadError.self) {
            try finalizer.finish(rom: rom(), files: files, destination: destination)
        }
    }

    @Test func cleanUpRemovesADirectoryItCreatedItself() async throws {
        let root = makeRoot()
        defer { remove(root) }
        let finalizer = ROMDownloadFinalizer(
            repository: FakeLocalROMs(romsBaseURL: root),
            storageProbe: FakeStorageProbe(availableBytes: 1_000)
        )
        let files = [file("red.gb", size: 10)]

        let destination = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 0)
        write("red.gb", bytes: 4, in: destination.directoryURL)
        #expect(destination.didCreateDirectory)

        finalizer.cleanUp(destination)

        #expect(!FileManager.default.fileExists(atPath: destination.directoryURL.path))
    }

    /// A directory that was already there can hold files of an earlier download,
    /// so cleanup must only take back what this download wrote.
    @Test func cleanUpKeepsFilesItDoesNotOwn() async throws {
        let root = makeRoot()
        defer { remove(root) }
        let finalizer = ROMDownloadFinalizer(
            repository: FakeLocalROMs(romsBaseURL: root),
            storageProbe: FakeStorageProbe(availableBytes: 1_000)
        )
        let existingDirectory = root.appendingPathComponent("gb/Pokemon Red", isDirectory: true)
        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        write("blue.gb", bytes: 8, in: existingDirectory)

        let files = [file("red.gb", size: 10)]
        let destination = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 0)
        write("red.gb", bytes: 4, in: destination.directoryURL)
        #expect(!destination.didCreateDirectory)

        finalizer.cleanUp(destination)

        #expect(!FileManager.default.fileExists(atPath: destination.directoryURL.appendingPathComponent("red.gb").path))
        #expect(FileManager.default.fileExists(atPath: existingDirectory.appendingPathComponent("blue.gb").path))
    }

    @Test func storageCheckCountsBytesReservedByOtherDownloads() async throws {
        let root = makeRoot()
        defer { remove(root) }
        let probe = FakeStorageProbe(availableBytes: 100)
        let finalizer = ROMDownloadFinalizer(
            repository: FakeLocalROMs(romsBaseURL: root),
            storageProbe: probe
        )
        let files = [file("red.gb", size: 60)]

        // On its own the ROM fits.
        _ = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 0)
        #expect(probe.requestedBytes == 60)

        // Together with another download that is open but not written yet it does not.
        do {
            _ = try await finalizer.prepare(rom: rom(), files: files, reservedBytes: 60)
            Issue.record("Expected the reserved bytes to exhaust the volume")
        } catch let error as LocalROMDownloadError {
            guard case .insufficientStorage(let required, let available) = error else {
                Issue.record("Expected insufficientStorage, got \(error)")
                return
            }
            #expect(required == 120)
            #expect(available == 100)
        }
        #expect(probe.requestedBytes == 120)
    }
}
