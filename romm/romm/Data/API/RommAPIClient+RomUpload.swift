//
//  RommAPIClient+RomUpload.swift
//  romm
//
//  Chunked ROM upload (RomM 4.8.0+). Each call builds its own request rather
//  than going through `makeRequest`/`multipartRequest`: the start call needs
//  custom headers plus a JSON body, the chunk call needs per-chunk progress
//  from `uploadTask(with:fromFile:)`, and cancel is deliberately best-effort.
//

import Foundation

// MARK: - ROM Upload API
extension RommAPIClient {

    private struct UploadStartResponse: Codable {
        let uploadId: String
        enum CodingKeys: String, CodingKey { case uploadId = "upload_id" }
    }

    func startRomUpload(platformId: Int, fileName: String, fileSize: Int64, totalChunks: Int) async throws -> String {
        let url = try buildURL(path: "api/roms/upload/start")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(try makeAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(platformId), forHTTPHeaderField: "x-upload-platform")
        request.setValue(Self.percentEncode(fileName), forHTTPHeaderField: "x-upload-filename")
        request.setValue(String(fileSize), forHTTPHeaderField: "x-upload-total-size")
        request.setValue(String(totalChunks), forHTTPHeaderField: "x-upload-total-chunks")
        request.httpBody = try JSONEncoder().encode(["filename": fileName])
        request.timeoutInterval = 30

        let (data, response) = try await urlSession.data(for: request)
        let http = try Self.asHTTPResponse(response)
        try Self.validateUploadResponse(http, data: data)
        do {
            return try JSONDecoder().decode(UploadStartResponse.self, from: data).uploadId
        } catch {
            throw APIClientError.decodingError(error)
        }
    }

    func uploadRomChunk(
        uploadId: String,
        index: Int,
        fileURL: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        let url = try buildURL(path: "api/roms/upload/\(uploadId)")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.put.rawValue
        request.setValue(try makeAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(index), forHTTPHeaderField: "x-chunk-index")
        request.timeoutInterval = 120

        let delegate = RomUploadProgressDelegate(progressHandler: progressHandler)
        let session = URLSession(configuration: urlSession.configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let task = session.uploadTask(with: request, fromFile: fileURL)
        // Cancelling the ROM upload job needs to stop the in-flight chunk
        // right away, not just the state machine driving it, so an upload
        // that was told to stop does not keep spending bandwidth on a chunk
        // nobody wants anymore.
        let (data, response) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                delegate.completion = { continuation.resume(with: $0) }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        let http = try Self.asHTTPResponse(response)
        try Self.validateUploadResponse(http, data: data)
    }

    func completeRomUpload(uploadId: String) async throws {
        let url = try buildURL(path: "api/roms/upload/\(uploadId)/complete")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(try makeAuthHeader(), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await urlSession.data(for: request)
        let http = try Self.asHTTPResponse(response)
        try Self.validateUploadResponse(http, data: data)
    }

    /// Best-effort and idempotent: the server treats cancelling a session it no
    /// longer knows about (already completed, already expired) the same as a
    /// successful cancel, and a caller clearing up after itself has no use for
    /// a thrown error either way.
    func cancelRomUpload(uploadId: String) async throws {
        let url = try buildURL(path: "api/roms/upload/\(uploadId)/cancel")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(try makeAuthHeader(), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        _ = try? await urlSession.data(for: request)
    }

    // MARK: - Helpers

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func asHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.networkError(URLError(.badServerResponse))
        }
        return http
    }

    /// The upload session TTL is 24h server side, and its cache can also be
    /// flushed; either shows up as this status/message pair. `"Missing
    /// chunks"` is excluded even though it is also a 400: it means our own
    /// chunk accounting is wrong, which restarting from scratch would mask
    /// rather than fix, so it is left to surface as a hard failure instead.
    private static func validateUploadResponse(_ http: HTTPURLResponse, data: Data) throws {
        guard !(200...299).contains(http.statusCode) else { return }
        let message = String(data: data, encoding: .utf8) ?? ""
        if http.statusCode == 401 {
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
            throw APIClientError.authenticationRequired
        }
        if http.statusCode == 400, message.contains("already exists") {
            throw RomUploadError.duplicateFileName
        }
        if http.statusCode == 404 {
            throw RomUploadError.sessionExpired
        }
        if http.statusCode == 400, !message.contains("Missing chunks") {
            throw RomUploadError.sessionExpired
        }
        throw APIClientError.invalidResponse(http.statusCode, message)
    }
}

/// Reports `uploadTask(with:fromFile:)` progress. The response body here is
/// always small JSON (or empty), so it is buffered in memory rather than
/// streamed to disk like `DownloadProgressDelegate`.
///
/// Inherits the private-network certificate handling so chunk uploads keep
/// working against self-signed servers on Tailscale and local addresses.
final class RomUploadProgressDelegate: PrivateNetworkURLSessionDelegate, URLSessionDataDelegate {
    private let progressHandler: ((Double) -> Void)?
    private var responseData = Data()
    private var response: URLResponse?

    var completion: ((Result<(Data, URLResponse), Error>) -> Void)?

    init(progressHandler: ((Double) -> Void)?) {
        self.progressHandler = progressHandler
        super.init()
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
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
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        progressHandler?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        guard let response else {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        finish(.success((responseData, response)))
    }
}
