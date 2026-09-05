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

    /// Rate is measured over a window rather than since the start, so a slow
    /// patch late in a large download is actually visible.
    private var windowStart: Date?
    private var windowStartBytes: Int64 = 0
    private var currentRate: Double?
    private static let rateWindow: TimeInterval = 1.0

    /// Throttled so a fast local server does not post thousands of updates.
    private var lastReport: Date?
    private static let reportInterval: TimeInterval = 0.1

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
            windowStart = Date()
            windowStartBytes = 0
        } catch {
            completionHandler(.cancel)
            completion?(.failure(error))
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
            completion?(.failure(error))
            return
        }
        receivedBytes += Int64(data.count)
        reportProgress()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil

        if let error {
            completion?(.failure(error))
            return
        }
        guard let response else {
            completion?(.failure(URLError(.badServerResponse)))
            return
        }
        // A final report, so the bar lands exactly on the number of bytes that
        // actually arrived rather than wherever throttling left it.
        progressHandler?(receivedBytes, expectedSize, currentRate)
        completion?(.success((destinationURL, response)))
    }

    /// Body of a non-2xx response, so the caller can surface the server's message.
    private(set) var errorBody = Data()

    private func reportProgress() {
        let now = Date()

        if let windowStart, now.timeIntervalSince(windowStart) >= Self.rateWindow {
            let elapsed = now.timeIntervalSince(windowStart)
            currentRate = Double(receivedBytes - windowStartBytes) / elapsed
            self.windowStart = now
            windowStartBytes = receivedBytes
        }

        if let lastReport, now.timeIntervalSince(lastReport) < Self.reportInterval {
            return
        }
        lastReport = now
        progressHandler?(receivedBytes, expectedSize, currentRate)
    }
}
