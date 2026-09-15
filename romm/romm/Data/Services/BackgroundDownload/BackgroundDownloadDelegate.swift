//
//  BackgroundDownloadDelegate.swift
//  romm
//

import Foundation

/// Turns a background session's callbacks into `PBackgroundDownloadEventSink`
/// calls, and puts every file that arrives where it belongs. Inherits the
/// private-network certificate handling, so downloads keep working against
/// self-signed servers on Tailscale and local addresses.
///
/// `URLSessionDownloadDelegate`'s requirements are nonisolated, so every
/// callback enters the main actor with `MainActor.assumeIsolated`, which holds
/// because the session's delegate queue is the main queue and nothing else calls
/// these methods. Each one hands straight over to a main actor method taking
/// plain values, which is also what the tests drive. The class itself stays
/// unannotated and takes its isolation from `PrivateNetworkURLSessionDelegate`.
final class BackgroundDownloadDelegate: PrivateNetworkURLSessionDelegate, URLSessionDownloadDelegate {

    /// Upper bound on how much of a rejected response is read into memory. A
    /// rejection carries a short message; anything bigger is not a message, and
    /// the device may be finishing a multi gigabyte transfer at the same time.
    static let maxServerMessageBytes = 64 * 1024

    /// Weak, because the sink owns the session that owns this delegate.
    weak var eventSink: PBackgroundDownloadEventSink?

    /// Strong, because `PDownloadDestinationResolver` is not class bound and so
    /// cannot be weak. The session it belongs to lives as long as the process,
    /// so this keeps nothing alive that would otherwise go away.
    var destinationResolver: PDownloadDestinationResolver?

    /// One meter per transfer in flight, keyed by `DownloadTaskKey.rawValue`
    /// because the key itself is not `Hashable`. Dropped when its transfer ends.
    private var rateMeters: [String: TransferRateMeter] = [:]

    /// The handler the system hands over when it relaunches the app only to
    /// deliver session events. Consumed on first use: calling it twice is a
    /// fault, and it only means anything once per relaunch.
    private var launchCompletionHandler: (() -> Void)?

    private let logger = Logger.network
    private let fileManager = FileManager.default

    func setLaunchCompletionHandler(_ handler: @escaping () -> Void) {
        launchCompletionHandler = handler
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        MainActor.assumeIsolated {
            finishDownload(
                key: downloadTask.taskDescription.flatMap(DownloadTaskKey.init(rawValue:)),
                statusCode: (downloadTask.response as? HTTPURLResponse)?.statusCode,
                location: location
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            // `totalBytesExpectedToWrite` is left alone on purpose: RomM builds
            // archives while it serves them, so it is usually
            // `NSURLSessionTransferSizeUnknown`. The size to measure against
            // comes from the ROM metadata, which the sink has.
            recordProgress(
                key: downloadTask.taskDescription.flatMap(DownloadTaskKey.init(rawValue:)),
                totalBytesWritten: totalBytesWritten,
                at: Date()
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        MainActor.assumeIsolated {
            completeTransfer(
                key: task.taskDescription.flatMap(DownloadTaskKey.init(rawValue:)),
                error: error
            )
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            handleSessionDidFinishEvents()
        }
    }

    // MARK: - Handling

    /// Deals with a transfer that produced a file, either by moving it into place
    /// or by getting rid of it.
    ///
    /// URLSession deletes `location` as soon as this call returns, which is why
    /// the move below is a plain synchronous `moveItem` with no `Task`, no `await`
    /// and no dispatch around it: pushing the move off this call stack loses the
    /// whole download at the finish line, however many gigabytes it was.
    ///
    /// `statusCode` is nil for a response that is not HTTP, which has no status
    /// to reject on and counts as a success.
    @MainActor
    func finishDownload(key: DownloadTaskKey?, statusCode: Int?, location: URL) {
        guard let key else {
            // The task carries no description this app wrote, so it is left over
            // from an earlier install and nothing claims its file.
            logger.warning("Background download finished without a usable task key, discarding file")
            discard(location)
            return
        }

        if let statusCode, !(200...299).contains(statusCode) {
            reportRejection(key: key, statusCode: statusCode, body: location)
            return
        }

        guard let destination = destinationResolver?.destinationURL(for: key) else {
            // The job is gone, for instance cancelled while the file was still
            // arriving. There is nowhere to put the file and nobody to tell.
            logger.info("No destination for finished download of \(key.fileName), discarding file")
            discard(location)
            return
        }

        do {
            try move(location, to: destination)
        } catch {
            logger.error("Failed to move finished download of \(key.fileName): \(error)")
            discard(location)
            eventSink?.downloadFailed(key: key, error: error, isCancellation: false)
            return
        }

        eventSink?.downloadFinished(key: key, bytesOnDisk: sizeOnDisk(of: destination))
    }

    /// Reports a checkpoint, throttled by the transfer's own meter.
    ///
    /// `now` is a parameter so the rate can be tested without waiting on a clock.
    @MainActor
    func recordProgress(key: DownloadTaskKey?, totalBytesWritten: Int64, at now: Date) {
        guard let key else { return }

        var meter = rateMeters[key.rawValue] ?? {
            var fresh = TransferRateMeter()
            fresh.start(at: now)
            return fresh
        }()
        let rate = meter.record(totalBytes: totalBytesWritten, at: now)
        let shouldReport = meter.shouldReport(at: now)
        rateMeters[key.rawValue] = meter

        guard shouldReport else { return }
        eventSink?.downloadProgressed(
            key: key,
            totalBytesWritten: totalBytesWritten,
            bytesPerSecond: rate
        )
    }

    /// Closes off a transfer, whether it got through or not.
    @MainActor
    func completeTransfer(key: DownloadTaskKey?, error: Error?) {
        guard let key else {
            if let error {
                logger.warning("Background transfer without a usable task key ended: \(error)")
            }
            return
        }

        rateMeters.removeValue(forKey: key.rawValue)

        // Without an error the file already went through `finishDownload`, which
        // has reported it. Reporting again here would count the transfer twice.
        guard let error else { return }

        let cancelled = isCancellation(error)
        logger.warning("Background download of \(key.fileName) ended: \(error), cancellation: \(cancelled)")
        eventSink?.downloadFailed(key: key, error: error, isCancellation: cancelled)
    }

    /// Tells the sink that the session is done, then releases the system back.
    @MainActor
    func handleSessionDidFinishEvents() {
        eventSink?.sessionDidFinishEvents()

        guard let handler = launchCompletionHandler else { return }
        launchCompletionHandler = nil
        handler()
    }

    // MARK: - Helpers

    /// Puts the arrived file at `destination`, replacing whatever is there, since
    /// that can only be a leftover from an interrupted attempt at the same
    /// download and `moveItem` would refuse to overwrite it.
    private func move(_ location: URL, to destination: URL) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: location, to: destination)
    }

    private func discard(_ location: URL) {
        try? fileManager.removeItem(at: location)
    }

    /// Bytes the moved file actually occupies. The announced size is not used:
    /// the server may build an archive while it serves it, so what landed on disk
    /// is the only number worth storing.
    private func sizeOnDisk(of url: URL) -> Int64 {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            logger.warning("Could not read the size of \(url.lastPathComponent) after moving it")
            return 0
        }
        return Int64(size)
    }

    /// Hands on a non-2xx response, whose file holds the server's error text
    /// rather than the payload and therefore goes.
    @MainActor
    private func reportRejection(key: DownloadTaskKey, statusCode: Int, body: URL) {
        let message = serverMessage(at: body)
        discard(body)

        if statusCode == 401 {
            // Same as the API client does for every other request. Without this,
            // an expired session makes downloads fail with no reason the user
            // could act on.
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
        }

        logger.warning("Background download of \(key.fileName) was rejected with status \(statusCode)")
        eventSink?.downloadRejected(key: key, statusCode: statusCode, serverMessage: message)
    }

    /// The server's message for a rejected transfer, read up to
    /// `maxServerMessageBytes` and never further.
    ///
    /// Decoded leniently, since a body cut off at the limit can end in the middle
    /// of a multi byte character.
    private func serverMessage(at location: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: location) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maxServerMessageBytes), !data.isEmpty else {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Whether the app asked for this transfer to stop, as opposed to it breaking.
    ///
    /// `URLError.backgroundSessionWasDisconnected` reads like a cancel but is not
    /// one: the session lost track of the task across a relaunch, so the job is
    /// allowed to run again instead of being written off as the user's decision.
    private func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled
    }
}
