import Testing
import Foundation
@testable import romm

struct DownloadJobStoreTests {

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadJobStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeJob(
        romId: Int,
        name: String = "Pokemon Red",
        fileNames: [String] = ["Pokemon Red (USA, Europe) [!].gb"]
    ) -> DownloadJob {
        DownloadJob(
            romId: romId,
            rom: DownloadJobRomSnapshot(
                id: romId,
                name: name,
                platformId: 3,
                platformSlug: "gb",
                urlCover: "https://example.invalid/cover.png",
                fileName: fileNames.first,
                sizeBytes: 1_048_576
            ),
            platformName: "Game Boy",
            romDirectoryPath: "Game Boy/\(name)",
            files: fileNames.enumerated().map { index, fileName in
                DownloadJobFile(fileName: fileName, expectedSizeBytes: Int64(1024 * (index + 1)))
            }
        )
    }

    private func queueFileURL(in root: URL) -> URL {
        root.appendingPathComponent(DownloadJobStore.queueFileName)
    }

    @Test func emptyDirectoryReadsAsAnEmptyQueue() {
        let root = makeRoot()
        defer { removeRoot(root) }
        #expect(DownloadJobStore(rootDirectory: root).allJobs().isEmpty)
    }

    /// The point of the store: a job written before the app was killed has to
    /// come back byte for byte when the app builds a fresh store on restart.
    @Test func jobWithSeveralFilesSurvivesASecondStore() {
        let root = makeRoot()
        defer { removeRoot(root) }
        var job = makeJob(
            romId: 7,
            fileNames: ["Disc 1 (of 2).chd", "Disc 2 (of 2).chd"]
        )
        job.state = .running
        job.restartCount = 2
        job.files[0].state = .downloaded
        job.files[0].receivedBytes = 4096
        job.files[0].usesLegacyContentPath = true
        job.files[1].state = .running
        job.files[1].receivedBytes = 512

        DownloadJobStore(rootDirectory: root).add(job)

        let reopened = DownloadJobStore(rootDirectory: root)
        #expect(reopened.allJobs() == [job])
        #expect(reopened.job(id: job.id) == job)
        #expect(reopened.job(romId: 7) == job)
    }

    @Test func unknownLookupsReturnNil() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        store.add(makeJob(romId: 7))
        #expect(store.job(id: UUID()) == nil)
        #expect(store.job(romId: 8) == nil)
    }

    /// A queue file that cannot be decoded must not stop the app from starting,
    /// so it reads as an empty queue.
    @Test func corruptQueueFileReadsAsAnEmptyQueue() throws {
        let root = makeRoot()
        defer { removeRoot(root) }
        try Data("{ this is not the queue".utf8).write(to: queueFileURL(in: root))
        #expect(DownloadJobStore(rootDirectory: root).allJobs().isEmpty)
    }

    /// Valid JSON that is not a job list is just as broken as a truncated file.
    @Test func unexpectedJSONReadsAsAnEmptyQueue() throws {
        let root = makeRoot()
        defer { removeRoot(root) }
        try Data(#"{"jobs": []}"#.utf8).write(to: queueFileURL(in: root))
        #expect(DownloadJobStore(rootDirectory: root).allJobs().isEmpty)
    }

    @Test func addKeepsTheOrderJobsWereAddedIn() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let first = makeJob(romId: 1, name: "First")
        let second = makeJob(romId: 2, name: "Second")
        store.add(first)
        store.add(second)
        #expect(store.allJobs().map(\.romId) == [1, 2])
    }

    @Test func addingTheSameJobTwiceKeepsOneEntry() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let job = makeJob(romId: 7)
        store.add(job)
        store.add(job)
        #expect(store.allJobs() == [job])
    }

    @Test func replacingAJobLeavesTheOtherJobsAlone() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let untouched = makeJob(romId: 1, name: "Untouched")
        var changed = makeJob(romId: 2, name: "Changed")
        store.add(untouched)
        store.add(changed)

        changed.state = .finalizing
        store.replace(changed)

        #expect(store.job(id: untouched.id) == untouched)
        #expect(store.job(id: changed.id)?.state == .finalizing)
    }

    @Test func replacingAnUnknownJobChangesNothing() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let job = makeJob(romId: 1)
        store.add(job)

        store.replace(makeJob(romId: 99, name: "Never queued"))

        #expect(store.allJobs() == [job])
    }

    /// Progress checkpoints land on one file at a time and must not carry the
    /// rest of the queue with them.
    @Test func updatingOneFileLeavesTheOtherJobsAndFilesAlone() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let untouched = makeJob(romId: 1, name: "Untouched")
        let job = makeJob(romId: 2, name: "Two Discs", fileNames: ["Disc 1.chd", "Disc 2.chd"])
        store.add(untouched)
        store.add(job)

        store.updateFile(jobId: job.id, fileName: "Disc 2.chd") { file in
            file.state = .running
            file.receivedBytes = 900
        }

        let updated = store.job(id: job.id)
        #expect(updated?.files.first?.state == .pending)
        #expect(updated?.files.first?.receivedBytes == 0)
        #expect(updated?.files.last?.state == .running)
        #expect(updated?.files.last?.receivedBytes == 900)
        #expect(store.job(id: untouched.id) == untouched)
    }

    @Test func updatingAnUnknownFileChangesNothing() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let job = makeJob(romId: 7)
        store.add(job)

        store.updateFile(jobId: job.id, fileName: "not-in-this-job.gb") { $0.receivedBytes = 1 }
        store.updateFile(jobId: UUID(), fileName: job.files[0].fileName) { $0.receivedBytes = 1 }

        #expect(store.allJobs() == [job])
    }

    @Test func removedJobIsGoneAndTheFileStaysValidJSON() throws {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let kept = makeJob(romId: 1, name: "Kept")
        let removed = makeJob(romId: 2, name: "Removed")
        store.add(kept)
        store.add(removed)

        store.remove(jobId: removed.id)

        #expect(store.job(id: removed.id) == nil)
        #expect(store.allJobs() == [kept])

        let data = try Data(contentsOf: queueFileURL(in: root))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [Any]
        #expect(decoded?.count == 1)
        #expect(DownloadJobStore(rootDirectory: root).allJobs() == [kept])
    }

    @Test func removingAnUnknownJobIsHarmless() {
        let root = makeRoot()
        defer { removeRoot(root) }
        let store = DownloadJobStore(rootDirectory: root)
        let job = makeJob(romId: 7)
        store.add(job)
        store.remove(jobId: UUID())
        #expect(store.allJobs() == [job])
    }

    // MARK: - Queue file compatibility

    /// Every app version up to now wrote a `taskIdentifier` per file. The field
    /// is gone, and a queue file that still carries one has to keep decoding:
    /// dropping it would mean losing every download in flight on update.
    @Test func aQueueFileWithATaskIdentifierPerFileStillDecodes() throws {
        let root = makeRoot()
        defer { removeRoot(root) }
        let json = """
        [
          {
            "id": "8E1F4C0A-2B7D-4E55-9A18-77C3D4E5F601",
            "romId": 7,
            "rom": { "id": 7, "name": "Pokemon Red", "platformId": 3, "platformSlug": "gb" },
            "platformName": "Game Boy",
            "romDirectoryPath": "Game Boy/Pokemon Red",
            "createdAt": 0,
            "state": "running",
            "restartCount": 0,
            "files": [
              {
                "fileName": "red.gb",
                "expectedSizeBytes": 1024,
                "usesLegacyContentPath": false,
                "state": "running",
                "receivedBytes": 512,
                "taskIdentifier": 42
              }
            ]
          }
        ]
        """
        try Data(json.utf8).write(to: queueFileURL(in: root))

        let jobs = DownloadJobStore(rootDirectory: root).allJobs()

        let job = try #require(jobs.first)
        #expect(jobs.count == 1)
        #expect(job.romDirectoryPath == "Game Boy/Pokemon Red")
        #expect(job.files.map(\.receivedBytes) == [512])
        #expect(job.files.map(\.state) == [.running])
    }

    // MARK: - Task keys

    /// ROM file names bring brackets, dots, spaces and the odd separator along,
    /// and the key still has to come back exactly as it went in.
    @Test func taskKeySurvivesAMeanFileName() {
        let key = DownloadTaskKey(
            jobId: UUID(),
            fileName: "Legend of Zelda, The | Ōkami (Japan) (v1.1) [T+Eng1.0_Someone].zip"
        )
        #expect(DownloadTaskKey(rawValue: key.rawValue) == key)
        #expect(DownloadTaskKey(rawValue: key.rawValue)?.fileName == key.fileName)
    }

    @Test func taskKeySurvivesAFileNameThatIsOnlySeparators() {
        let key = DownloadTaskKey(jobId: UUID(), fileName: "|||")
        #expect(DownloadTaskKey(rawValue: key.rawValue) == key)
    }

    @Test func garbageTaskDescriptionsParseToNil() {
        #expect(DownloadTaskKey(rawValue: "") == nil)
        #expect(DownloadTaskKey(rawValue: "no separator here") == nil)
        #expect(DownloadTaskKey(rawValue: "not-a-uuid|file.gb") == nil)
        #expect(DownloadTaskKey(rawValue: "|file.gb") == nil)
        // A job id without a file name names no file, so it is not a key.
        #expect(DownloadTaskKey(rawValue: "\(UUID().uuidString)|") == nil)
    }

    /// Task descriptions of tasks the app did not create end up here too, and a
    /// truncated key must not be read as a shorter one.
    @Test func truncatedTaskKeyParsesToNil() {
        let key = DownloadTaskKey(jobId: UUID(), fileName: "file.gb")
        let truncated = String(key.rawValue.dropFirst(4))
        #expect(DownloadTaskKey(rawValue: truncated) == nil)
    }

    // MARK: - ROM snapshot

    @MainActor
    @Test func snapshotRebuildsTheRomFieldsItCarries() {
        let rom = Rom(
            id: 7,
            name: "Pokemon Red",
            platformId: 3,
            urlCover: "https://example.invalid/cover.png",
            sizeBytes: 1_048_576,
            fileName: "Pokemon Red (USA, Europe) [!].gb",
            platformSlug: "gb"
        )
        let rebuilt = DownloadJobRomSnapshot(rom: rom).toRom()
        #expect(rebuilt.id == rom.id)
        #expect(rebuilt.name == rom.name)
        #expect(rebuilt.platformId == rom.platformId)
        #expect(rebuilt.platformSlug == rom.platformSlug)
        #expect(rebuilt.urlCover == rom.urlCover)
        #expect(rebuilt.fileName == rom.fileName)
        #expect(rebuilt.sizeBytes == rom.sizeBytes)
    }
}
