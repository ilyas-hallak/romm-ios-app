//
//  BackgroundDownloadEvents.swift
//  romm
//

import Foundation

/// What the background session's delegate reports about a single file transfer.
///
/// The delegate owns the URLSession side, the sink owns the job state, which
/// keeps both halves testable on their own: the sink without a network, the
/// delegate without a queue. The delegate also moves a finished file into place
/// itself, so by the time `downloadFinished` arrives the bytes are already at
/// their destination.
@MainActor
protocol PBackgroundDownloadEventSink: AnyObject {
    /// A checkpoint while the transfer runs. `bytesPerSecond` is nil until a rate
    /// could be measured.
    func downloadProgressed(key: DownloadTaskKey, totalBytesWritten: Int64, bytesPerSecond: Double?)

    /// The file arrived and has been moved to its destination. `bytesOnDisk` is
    /// what was actually written, which can differ from the announced size, since
    /// the server may build archives while serving them.
    func downloadFinished(key: DownloadTaskKey, bytesOnDisk: Int64)

    /// The transfer ended without a usable file. `isCancellation` separates a
    /// cancel the app asked for from a genuine failure, so the first is not
    /// reported to the user as an error.
    func downloadFailed(key: DownloadTaskKey, error: Error, isCancellation: Bool)

    /// The server answered, but not with the file. `serverMessage` is the response
    /// body when it was small enough to be worth keeping.
    ///
    /// A 404 is the interesting case: it means the per-file content path is not
    /// available and the legacy path has to be tried, which is the sink's call to
    /// make, not the delegate's.
    func downloadRejected(key: DownloadTaskKey, statusCode: Int, serverMessage: String?)

    /// Every transfer the session had queued has been dealt with. When the app
    /// was relaunched in the background to be told this, it must call the launch
    /// completion handler once this returns, or the system will fault it.
    func sessionDidFinishEvents()
}

/// The session as its driver needs it: start a transfer, stop one, and find out
/// what the system still has in flight.
///
/// Behind this sits one background `URLSession` with a fixed identifier, which
/// the system keeps transferring for while the app is suspended. A fake standing
/// in for it lets the whole queue be tested without a server.
@MainActor
protocol PBackgroundTransferClient: AnyObject {
    /// The session identifier the system uses to address this client. Asked for
    /// when the app is relaunched for session events, so the client itself
    /// answers whether the events are its own.
    var identifier: String { get }

    /// Set before the first transfer starts. Held weakly by the implementation,
    /// since the sink outlives individual transfers and the two refer to each
    /// other.
    var eventSink: PBackgroundDownloadEventSink? { get set }
    var destinationResolver: PDownloadDestinationResolver? { get set }

    /// Starts a transfer and tags it with `key`, so it can be matched back to its
    /// job after the app has been restarted.
    func start(request: URLRequest, key: DownloadTaskKey)

    /// Stops every transfer belonging to a job. Reports each one through
    /// `downloadFailed(isCancellation: true)`.
    func cancelTransfers(forJobId jobId: UUID)

    /// The keys of the transfers the system is still holding for this session.
    ///
    /// After a relaunch this is the only truthful account of what is running:
    /// the store says what the app last knew, this says what actually survived.
    func liveTransferKeys() async -> [DownloadTaskKey]

    /// Stashes the completion handler the system hands over when it relaunches
    /// the app just to deliver session events. Called once all events are in.
    func setLaunchCompletionHandler(_ handler: @escaping () -> Void)
}

/// Where a finished transfer has to be put, resolved synchronously.
///
/// `didFinishDownloadingTo` gives up its temporary file the moment the method
/// returns, so the destination cannot be awaited. Working it out needs the job
/// store and the ROM library root, and neither read touches the network.
@MainActor
protocol PDownloadDestinationResolver {
    /// Absolute destination for a transfer, or nil when the job is no longer
    /// known, for instance because it was cancelled while the file was arriving.
    func destinationURL(for key: DownloadTaskKey) -> URL?
}
