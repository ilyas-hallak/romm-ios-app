import Foundation
@testable import romm

/// The download queue with no file system behind it: every job lives in memory.
///
/// Shared between `DownloadQueueManagerTests` and `RomDetailViewModelTests`, so a
/// test that needs a real `.failed` or `.running` row can seed one instead of
/// relying on a store that always answers nil.
final class QueueJobStore: PDownloadJobStore, @unchecked Sendable {
    private var jobs: [DownloadJob] = []

    func allJobs() -> [DownloadJob] { jobs }
    func job(id: UUID) -> DownloadJob? { jobs.first { $0.id == id } }
    func job(romId: Int) -> DownloadJob? { jobs.first { $0.romId == romId } }

    func add(_ job: DownloadJob) {
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
    }

    func replace(_ job: DownloadJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
    }

    func updateFile(jobId: UUID, fileName: String, _ mutate: (inout DownloadJobFile) -> Void) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobId }),
              let fileIndex = jobs[jobIndex].files.firstIndex(where: { $0.fileName == fileName }) else { return }
        mutate(&jobs[jobIndex].files[fileIndex])
    }

    func remove(jobId: UUID) {
        jobs.removeAll { $0.id == jobId }
    }
}

/// Builds a `DownloadJob` fixture for a given state, so a test can seed a
/// `QueueJobStore` with a job that reads back as `.failed`, `.running`, and so on.
func job(
    romId: Int = 7,
    name: String = "Pokemon Red",
    state: DownloadJobState,
    expectedSizeBytes: Int64 = 100,
    receivedBytes: Int64 = 0,
    errorMessage: String? = nil
) -> DownloadJob {
    DownloadJob(
        romId: romId,
        rom: DownloadJobRomSnapshot(id: romId, name: name, platformId: 3, platformSlug: "gb"),
        platformName: "Game Boy",
        romDirectoryPath: "Game Boy/\(name)",
        state: state,
        files: [
            DownloadJobFile(
                fileName: "red.gb",
                expectedSizeBytes: expectedSizeBytes,
                state: state == .failed ? .failed : .running,
                receivedBytes: receivedBytes
            )
        ],
        errorMessage: errorMessage
    )
}

/// Hands out a request for any download path, so a seeded job can be retried
/// or resumed without reaching the network.
final class DownloadRequestAPIClient: StubRommAPIClient {
    override func makeDownloadRequest(path: String) throws -> URLRequest {
        URLRequest(url: URL(string: "https://romm.invalid/\(path)")!)
    }
}
