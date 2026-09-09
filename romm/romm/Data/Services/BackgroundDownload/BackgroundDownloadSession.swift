//
//  BackgroundDownloadSession.swift
//  romm
//

import Foundation

/// The app's one background `URLSession`, wrapped so its driver only sees
/// transfers, not URLSession.
///
/// The system keeps this session's transfers going while the app is suspended
/// and relaunches the app to report the outcome. Hence one session per
/// identifier and process: a second session claiming the same identifier is
/// handed the same transfers, and both would act on them. No `UIBackgroundModes`
/// entry or capability is involved, the bytes never move inside the app process.
@MainActor
final class BackgroundDownloadSession: PBackgroundTransferClient {

    /// Identifier of the session the app uses, derived from the bundle id so
    /// builds with different bundle ids on one device never adopt each other's
    /// transfers.
    ///
    /// Nonisolated because the app delegate is handed this identifier as a plain
    /// string when the system relaunches the app for session events.
    nonisolated static let defaultIdentifier =
        "\(Bundle.main.bundleIdentifier ?? "com.romm.app").background-downloads"

    /// The session the app runs its downloads through, and the only one outside
    /// tests, see `defaultIdentifier`.
    static let shared = BackgroundDownloadSession(identifier: defaultIdentifier)

    let identifier: String

    private let session: URLSession

    /// Kept as the concrete type, because the sink, the resolver and the launch
    /// handler are forwarded to it.
    private let delegate: BackgroundDownloadDelegate

    var eventSink: PBackgroundDownloadEventSink? {
        get { delegate.eventSink }
        set { delegate.eventSink = newValue }
    }

    var destinationResolver: PDownloadDestinationResolver? {
        get { delegate.destinationResolver }
        set { delegate.destinationResolver = newValue }
    }

    /// Takes its identifier so a test can run a session under a name nothing else
    /// uses. Production code goes through `shared`.
    init(identifier: String) {
        self.identifier = identifier

        let delegate = BackgroundDownloadDelegate()
        self.delegate = delegate

        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        // Lets the system relaunch the app in the background to hand over the
        // events of transfers that finished while the app was gone.
        configuration.sessionSendsLaunchEvents = true
        // The user started these downloads and is watching them, so they must not
        // be deferred to whenever the system finds it convenient.
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 3

        // The main queue, because the job state these callbacks feed lives on the
        // main actor and because the finished file has to be moved on the same
        // call stack that lent out its temporary URL.
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
    }

    func start(request: URLRequest, key: DownloadTaskKey) {
        let task = session.downloadTask(with: request)
        // The only tie between a task and its job that survives an app restart.
        // `taskIdentifier` is unique within one session and is handed out again,
        // while the description comes back with the task when the system
        // reconnects the recreated session to its transfers.
        task.taskDescription = key.rawValue
        task.resume()
    }

    func cancelTransfers(forJobId jobId: UUID) {
        // The task list can only be had asynchronously, so cancelling lands a
        // moment later. Each cancelled task still reports through
        // `didCompleteWithError` with `URLError.cancelled`, which is where the
        // job hears that it stopped.
        Task {
            for task in await session.allTasks {
                guard let description = task.taskDescription,
                      let key = DownloadTaskKey(rawValue: description),
                      key.jobId == jobId
                else { continue }
                task.cancel()
            }
        }
    }

    func liveTransferKeys() async -> [DownloadTaskKey] {
        await session.allTasks
            .filter { $0.state != .completed }
            .compactMap { $0.taskDescription.flatMap(DownloadTaskKey.init(rawValue:)) }
    }

    func setLaunchCompletionHandler(_ handler: @escaping () -> Void) {
        delegate.setLaunchCompletionHandler(handler)
    }
}
