//
//  FakeBackgroundTransferClient.swift
//  rommTests
//
//  Shared test double for PBackgroundTransferClient.
//

import Foundation
@testable import romm

/// Records what the coordinator asked the background session to do and lets a
/// test say what the system is supposedly still transferring.
///
/// Nothing here touches the network or the file system: a transfer is a recorded
/// request, and its outcome is whatever the test then reports back through the
/// event sink.
@MainActor
final class FakeBackgroundTransferClient: PBackgroundTransferClient {

    /// Any identifier will do, it only has to be told apart from a foreign one.
    var identifier: String = "test.background-downloads"

    /// Held weakly like the real session does, since the sink owns this client.
    weak var eventSink: PBackgroundDownloadEventSink?
    var destinationResolver: PDownloadDestinationResolver?

    /// Every started transfer, in the order it was started.
    private(set) var startedTransfers: [(request: URLRequest, key: DownloadTaskKey)] = []
    /// Jobs whose transfers were cancelled, in the order the cancels came in.
    private(set) var cancelledJobIds: [UUID] = []
    /// What `liveTransferKeys()` reports. Empty stands for a fresh session, which
    /// is what the app sees after the user swiped it away.
    var liveKeys: [DownloadTaskKey] = []
    private(set) var launchCompletionHandler: (() -> Void)?

    func start(request: URLRequest, key: DownloadTaskKey) {
        startedTransfers.append((request: request, key: key))
    }

    func cancelTransfers(forJobId jobId: UUID) {
        cancelledJobIds.append(jobId)
    }

    func liveTransferKeys() async -> [DownloadTaskKey] {
        liveKeys
    }

    func setLaunchCompletionHandler(_ handler: @escaping () -> Void) {
        launchCompletionHandler = handler
    }

    // MARK: - Test helpers

    var startedKeys: [DownloadTaskKey] {
        startedTransfers.map(\.key)
    }

    var startedPaths: [String] {
        startedTransfers.compactMap { $0.request.url?.path }
    }

    func startCount(forFileNamed fileName: String) -> Int {
        startedTransfers.filter { $0.key.fileName == fileName }.count
    }

    func reset() {
        startedTransfers = []
        cancelledJobIds = []
    }
}
