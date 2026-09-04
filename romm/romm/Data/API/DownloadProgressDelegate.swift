//
//  DownloadProgressDelegate.swift
//  romm
//

import Foundation

/// Reports download progress from `didWriteData` rather than from the task's
/// `Progress` object.
///
/// `URLSessionDownloadTask.progress` only carries a meaningful total while the
/// server announces a `Content-Length`. RomM streams multi-file ROMs as a zip it
/// builds on the fly, so that header is often absent and the progress object
/// stops being a reliable source. `didWriteData` still reports every chunk, and
/// hands over the announced size as `totalBytesExpectedToWrite`.
///
/// Inherits the private-network certificate handling, since downloads have to
/// keep working against self-signed servers on Tailscale and local addresses.
final class DownloadProgressDelegate: PrivateNetworkURLSessionDelegate, URLSessionDownloadDelegate {

    /// Called with `(bytesWritten, totalBytesExpected)`. The total is passed on
    /// untouched, so it stays `NSURLSessionTransferSizeUnknown` (-1) when the
    /// server did not announce a size. Callers decide what unknown means.
    private let progressHandler: ((Int64, Int64) -> Void)?

    /// Resumes the caller once the download finished or failed.
    var completion: ((Result<(URL, URLResponse), Error>) -> Void)?

    /// Logged once per download so the field logs show which ROM types arrive
    /// without an announced size.
    private var hasLoggedExpectedSize = false

    init(progressHandler: ((Int64, Int64) -> Void)?) {
        self.progressHandler = progressHandler
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if !hasLoggedExpectedSize {
            hasLoggedExpectedSize = true
            let announced = totalBytesExpectedToWrite > 0
                ? "\(totalBytesExpectedToWrite) bytes"
                : "unknown (server announced no size)"
            Logger.network.debug("Download expected size: \(announced)")
        }
        progressHandler?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Moved synchronously: iOS deletes `location` the moment this callback
        // returns, and the continuation resumes asynchronously.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("romm-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: staged)
            completion?(.success((staged, downloadTask.response ?? URLResponse())))
        } catch {
            completion?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A finished download already resumed the caller in `didFinishDownloadingTo`;
        // this only has to cover the failure path.
        guard let error else { return }
        completion?(.failure(error))
    }
}
