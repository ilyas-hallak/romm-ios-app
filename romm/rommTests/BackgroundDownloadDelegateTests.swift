import Testing
import Foundation
@testable import romm

/// Writes down what the delegate reported, in order, so a test can assert both
/// the call it wanted and that nothing else happened.
@MainActor
private final class SpySink: PBackgroundDownloadEventSink {
    enum Event: Equatable {
        /// The rate is compared as "was there one", the exact number is
        /// `TransferRateMeter`'s business.
        case progressed(key: String, totalBytesWritten: Int64, hasRate: Bool)
        case finished(key: String, bytesOnDisk: Int64)
        case failed(key: String, isCancellation: Bool)
        case rejected(key: String, statusCode: Int, serverMessage: String?)
        case sessionDidFinishEvents
    }

    var events: [Event] = []

    func downloadProgressed(key: DownloadTaskKey, totalBytesWritten: Int64, bytesPerSecond: Double?) {
        events.append(
            .progressed(key: key.rawValue, totalBytesWritten: totalBytesWritten, hasRate: bytesPerSecond != nil)
        )
    }

    func downloadFinished(key: DownloadTaskKey, bytesOnDisk: Int64) {
        events.append(.finished(key: key.rawValue, bytesOnDisk: bytesOnDisk))
    }

    func downloadFailed(key: DownloadTaskKey, error: Error, isCancellation: Bool) {
        events.append(.failed(key: key.rawValue, isCancellation: isCancellation))
    }

    func downloadRejected(key: DownloadTaskKey, statusCode: Int, serverMessage: String?) {
        events.append(.rejected(key: key.rawValue, statusCode: statusCode, serverMessage: serverMessage))
    }

    func sessionDidFinishEvents() {
        events.append(.sessionDidFinishEvents)
    }
}

/// Answers with the destinations the test put in, and with nil for everything
/// else, which is what a job that has disappeared looks like.
@MainActor
private final class StubResolver: PDownloadDestinationResolver {
    var destinations: [String: URL] = [:]

    func destinationURL(for key: DownloadTaskKey) -> URL? {
        destinations[key.rawValue]
    }
}

/// Counts calls from closures that outlive the statement they were written in.
private final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func mark() { count += 1 }
}

@MainActor
struct BackgroundDownloadDelegateTests {

    // MARK: - Fixtures

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundDownloadDelegate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeKey(fileName: String = "Pokemon Red (USA, Europe) [!].gb") -> DownloadTaskKey {
        DownloadTaskKey(jobId: UUID(), fileName: fileName)
    }

    /// Stands in for the file URLSession hands over and takes away again.
    private func makeTempFile(in root: URL, bytes: Int, byte: UInt8 = 0xAB) -> URL {
        let url = root.appendingPathComponent("temp-\(UUID().uuidString)")
        try? Data(repeating: byte, count: bytes).write(to: url)
        return url
    }

    private func makeTempFile(in root: URL, text: String) -> URL {
        let url = root.appendingPathComponent("temp-\(UUID().uuidString)")
        try? Data(text.utf8).write(to: url)
        return url
    }

    private func makeDelegate(sink: SpySink, resolver: StubResolver) -> BackgroundDownloadDelegate {
        let delegate = BackgroundDownloadDelegate()
        delegate.eventSink = sink
        delegate.destinationResolver = resolver
        return delegate
    }

    private func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    // MARK: - Finished transfers

    /// The point of the delegate: the file is in place before the sink is told,
    /// and the size reported is the one on disk, not the one that was announced.
    @Test func movesTheFileToItsDestinationAndReportsTheSizeOnDisk() {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let resolver = StubResolver()
        let delegate = makeDelegate(sink: sink, resolver: resolver)
        let key = makeKey()
        let destination = root.appendingPathComponent("Game Boy/Pokemon Red/red.gb")
        resolver.destinations[key.rawValue] = destination
        let temporary = makeTempFile(in: root, bytes: 2048)

        delegate.finishDownload(key: key, statusCode: 200, location: temporary)

        #expect(sink.events == [.finished(key: key.rawValue, bytesOnDisk: 2048)])
        #expect(fileSize(destination) == 2048)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    /// A leftover from an interrupted attempt is overwritten, not placed beside
    /// the new file under a second name.
    @Test func replacesAFileAlreadySittingAtTheDestination() throws {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let resolver = StubResolver()
        let delegate = makeDelegate(sink: sink, resolver: resolver)
        let key = makeKey()
        let directory = root.appendingPathComponent("Game Boy/Pokemon Red", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("red.gb")
        try Data(repeating: 0x01, count: 10).write(to: destination)
        resolver.destinations[key.rawValue] = destination

        delegate.finishDownload(key: key, statusCode: 200, location: makeTempFile(in: root, bytes: 512))

        #expect(sink.events == [.finished(key: key.rawValue, bytesOnDisk: 512)])
        #expect(fileSize(destination) == 512)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents == ["red.gb"])
    }

    /// A non-2xx response leaves the server's text in the file, so nothing may be
    /// put into the ROM library and the sink has to hear the status.
    @Test func reportsARejectionAndKeepsTheDestinationEmpty() {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let resolver = StubResolver()
        let delegate = makeDelegate(sink: sink, resolver: resolver)
        let key = makeKey()
        let destination = root.appendingPathComponent("Game Boy/Pokemon Red/red.gb")
        resolver.destinations[key.rawValue] = destination
        let temporary = makeTempFile(in: root, text: "{\"detail\":\"Not found\"}")

        delegate.finishDownload(key: key, statusCode: 404, location: temporary)

        #expect(
            sink.events == [
                .rejected(key: key.rawValue, statusCode: 404, serverMessage: "{\"detail\":\"Not found\"}")
            ]
        )
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    /// A download must not let an expired session pass unnoticed, otherwise the
    /// user only sees a failed download and is never asked to sign in again.
    @Test func postsSessionExpiredOnAnUnauthorisedResponse() {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let key = makeKey()
        let posts = CallCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in posts.mark() }
        defer { NotificationCenter.default.removeObserver(observer) }

        delegate.finishDownload(
            key: key,
            statusCode: 401,
            location: makeTempFile(in: root, text: "Not authenticated")
        )

        #expect(
            sink.events == [
                .rejected(key: key.rawValue, statusCode: 401, serverMessage: "Not authenticated")
            ]
        )
        #expect(posts.count == 1)
    }

    /// A body that is not a message must not be pulled into memory, the device
    /// may be finishing a multi gigabyte transfer at the same time.
    @Test func capsTheServerMessageItReadsFromALargeBody() {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let key = makeKey()
        let oversized = String(repeating: "A", count: 200_000)

        delegate.finishDownload(key: key, statusCode: 500, location: makeTempFile(in: root, text: oversized))

        guard let event = sink.events.first,
              case let .rejected(_, statusCode, serverMessage) = event
        else {
            Issue.record("Expected a rejection, got \(sink.events)")
            return
        }
        #expect(statusCode == 500)
        #expect((serverMessage?.count ?? 0) <= BackgroundDownloadDelegate.maxServerMessageBytes)
    }

    /// The job was cancelled while the file was still arriving: there is nowhere
    /// to put it and nobody left to tell, and that has to stay quiet.
    @Test func discardsTheFileWhenNoDestinationCanBeResolved() {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let temporary = makeTempFile(in: root, bytes: 64)

        delegate.finishDownload(key: makeKey(), statusCode: 200, location: temporary)

        #expect(sink.events.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    /// A task from an earlier install of the app comes back with a description
    /// this app cannot read. It belongs to nobody, and must not take the app down.
    @Test func ignoresATaskWhoseDescriptionCannotBeParsed() {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        // A real task, so this goes through the delegate method itself rather than
        // past it. The task is never resumed, only its description is of interest.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: URL(string: "https://example.invalid/red.gb")!)
        task.taskDescription = "not-a-task-key"
        let temporary = makeTempFile(in: root, bytes: 64)

        delegate.urlSession(session, downloadTask: task, didFinishDownloadingTo: temporary)

        #expect(sink.events.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    // MARK: - Progress

    @Test func reportsProgressAndTheRateOnceAWindowHasClosed() {
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let key = makeKey()
        let start = Date()

        delegate.recordProgress(key: key, totalBytesWritten: 1024, at: start)
        delegate.recordProgress(key: key, totalBytesWritten: 3072, at: start.addingTimeInterval(2))

        #expect(
            sink.events == [
                .progressed(key: key.rawValue, totalBytesWritten: 1024, hasRate: false),
                .progressed(key: key.rawValue, totalBytesWritten: 3072, hasRate: true)
            ]
        )
    }

    /// A background transfer produces callbacks far faster than a list can be
    /// redrawn, so reporting is throttled the same way the foreground download is.
    @Test func throttlesProgressReports() {
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let key = makeKey()
        let start = Date()

        delegate.recordProgress(key: key, totalBytesWritten: 1024, at: start)
        delegate.recordProgress(key: key, totalBytesWritten: 2048, at: start.addingTimeInterval(0.01))

        #expect(sink.events == [.progressed(key: key.rawValue, totalBytesWritten: 1024, hasRate: false)])
    }

    /// Nothing measured for a finished transfer may carry over into the next one
    /// under the same key, which is what a restarted download looks like.
    @Test func dropsTheRateMeterWhenATransferEnds() {
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let key = makeKey()
        let start = Date()

        delegate.recordProgress(key: key, totalBytesWritten: 1024, at: start)
        delegate.recordProgress(key: key, totalBytesWritten: 3072, at: start.addingTimeInterval(2))
        delegate.completeTransfer(key: key, error: URLError(.cancelled))
        delegate.recordProgress(key: key, totalBytesWritten: 128, at: start.addingTimeInterval(3))

        #expect(sink.events.last == .progressed(key: key.rawValue, totalBytesWritten: 128, hasRate: false))
    }

    // MARK: - Completion

    @Test func treatsAnAskedForCancelAsACancellation() {
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let key = makeKey()

        delegate.completeTransfer(key: key, error: URLError(.cancelled))

        #expect(sink.events == [.failed(key: key.rawValue, isCancellation: true)])
    }

    /// A session that lost its task across a relaunch is not the user's decision,
    /// so the job stays free to run again.
    @Test func treatsADisconnectedBackgroundSessionAsAFailure() {
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let key = makeKey()

        delegate.completeTransfer(key: key, error: URLError(.backgroundSessionWasDisconnected))

        #expect(sink.events == [.failed(key: key.rawValue, isCancellation: false)])
    }

    /// A successful transfer is reported when the file is moved, and the
    /// completion that follows it carries no error, so it must stay silent.
    @Test func doesNotReportASecondTimeAfterASuccessfulTransfer() {
        let root = makeRoot()
        defer { remove(root) }
        let sink = SpySink()
        let resolver = StubResolver()
        let delegate = makeDelegate(sink: sink, resolver: resolver)
        let key = makeKey()
        resolver.destinations[key.rawValue] = root.appendingPathComponent("Game Boy/Pokemon Red/red.gb")

        delegate.finishDownload(key: key, statusCode: 200, location: makeTempFile(in: root, bytes: 32))
        delegate.completeTransfer(key: key, error: nil)

        #expect(sink.events == [.finished(key: key.rawValue, bytesOnDisk: 32)])
    }

    // MARK: - Session events

    /// The system faults the app if the launch handler is called twice, so it is
    /// consumed on first use even though the events can arrive again.
    @Test func callsTheLaunchCompletionHandlerOnlyOnce() {
        let sink = SpySink()
        let delegate = makeDelegate(sink: sink, resolver: StubResolver())
        let handlerCalls = CallCounter()
        delegate.setLaunchCompletionHandler { handlerCalls.mark() }

        delegate.handleSessionDidFinishEvents()
        delegate.handleSessionDidFinishEvents()

        #expect(handlerCalls.count == 1)
        #expect(sink.events == [.sessionDidFinishEvents, .sessionDidFinishEvents])
    }
}
