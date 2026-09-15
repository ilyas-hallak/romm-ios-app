//
//  DownloadProgressDelegate.swift
//  romm
//

import Foundation

/// Streams a download to disk while counting the bytes itself.
///
/// Neither `URLSessionDownloadTask.progress` nor `didWriteData` can be relied on
/// here: RomM streams multi-file ROMs as a zip it builds on the fly, so no size
/// is announced, and the progress the system reports stops being meaningful. The
/// bytes still pass through this delegate on their way to disk, so counting them
/// here works regardless of what the server announced.
///
/// The expected size therefore comes from the caller (the ROM metadata) whenever
/// the response does not carry one.
///
/// Inherits the private-network certificate handling, since downloads have to
/// keep working against self-signed servers on Tailscale and local addresses.
final class DownloadProgressDelegate: PrivateNetworkURLSessionDelegate, URLSessionDataDelegate {

    /// Reports `(bytesWritten, totalBytesExpected, bytesPerSecond)`. The total is
    /// the announced size, or the caller's fallback, or -1 when neither is known.
    /// The rate is a moving average and is nil until enough time has passed to
    /// make it meaningful.
    private let progressHandler: ((Int64, Int64, Double?) -> Void)?

    /// Size the caller knows up front, used when the response announces none.
    private let fallbackExpectedSize: Int64

    /// Where the bytes are written as they arrive.
    private let destinationURL: URL
    private var fileHandle: FileHandle?

    private var expectedSize: Int64 = NSURLSessionTransferSizeUnknown
    private var receivedBytes: Int64 = 0
    private var response: URLResponse?

    /// Measures transfer rate over a sliding window and throttles reporting.
    private var rateMeter = TransferRateMeter()
    /// Cached rate from the meter, to avoid recalculating if the caller needs it
    /// after reporting is throttled.
    private var currentRate: Double?

    /// Body of a non-2xx response, so the caller can surface the server's message.
    private(set) var errorBody = Data()

    var completion: ((Result<(URL, URLResponse), Error>) -> Void)?

    init(
        destinationURL: URL,
        fallbackExpectedSize: Int64,
        progressHandler: ((Int64, Int64, Double?) -> Void)?
    ) {
        self.destinationURL = destinationURL
        self.fallbackExpectedSize = fallbackExpectedSize
        self.progressHandler = progressHandler
        super.init()
    }

    /// Resumes the caller exactly once.
    ///
    /// Cancelling the task on a write error still produces a
    /// `didCompleteWithError` afterwards, and resuming a checked continuation a
    /// second time traps, so the handler is consumed on first use.
    private func finish(_ result: Result<(URL, URLResponse), Error>) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response

        let announced = response.expectedContentLength
        if announced > 0 {
            expectedSize = announced
        } else if fallbackExpectedSize > 0 {
            // No Content-Length, so fall back to the size the ROM metadata knows.
            expectedSize = fallbackExpectedSize
        }
        Logger.network.debug(
            "Download expected size: announced=\(announced), fallback=\(self.fallbackExpectedSize), using=\(self.expectedSize)"
        )

        // Only success responses are streamed to the destination; error bodies
        // are small and collected in memory instead.
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.allow)
            return
        }

        do {
            try? FileManager.default.removeItem(at: destinationURL)
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: destinationURL)
            rateMeter.start(at: Date())
        } catch {
            completionHandler(.cancel)
            finish(.failure(error))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let fileHandle else {
            // Error response: keep the body so the caller can read the message.
            errorBody.append(data)
            return
        }
        do {
            try fileHandle.write(contentsOf: data)
        } catch {
            dataTask.cancel()
            finish(.failure(error))
            return
        }
        receivedBytes += Int64(data.count)
        reportProgress()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil

        if let error {
            finish(.failure(error))
            return
        }
        guard let response else {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        // A final report, so the bar lands exactly on the number of bytes that
        // actually arrived rather than wherever throttling left it.
        progressHandler?(receivedBytes, expectedSize, currentRate)
        finish(.success((destinationURL, response)))
    }

    private func reportProgress() {
        let now = Date()

        if let rate = rateMeter.record(totalBytes: receivedBytes, at: now) {
            currentRate = rate
        }

        if rateMeter.shouldReport(at: now) {
            progressHandler?(receivedBytes, expectedSize, currentRate)
        }
    }
}
