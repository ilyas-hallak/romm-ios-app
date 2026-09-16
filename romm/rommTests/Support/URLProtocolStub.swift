//
//  URLProtocolStub.swift
//  rommTests
//
//  A URLProtocol stub for HTTP-level tests: it intercepts requests a
//  URLSession would otherwise send, records what RommAPIClient actually sent
//  (method, headers, body), and hands back a canned response.
//

import Foundation
@testable import romm

/// One canned HTTP response.
struct StubbedResponse {
    var statusCode: Int
    var headers: [String: String] = [:]
    var body: Data = Data()
}

/// One HTTP exchange the stub protocol intercepted.
struct RecordedRequest {
    var url: URL
    var httpMethod: String
    var headers: [String: String]
    var body: Data?

    /// The URL's query, decoded into name/value pairs, in the order they
    /// appear. `nil` when a parameter has no `=value` (not used by this app).
    var queryItems: [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    /// Parses `body` as JSON into a dictionary, for asserting on raw keys
    /// rather than decoding back into the same Swift type.
    var jsonBody: [String: Any]? {
        guard let body else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

/// Keyed by host rather than a single shared slot, so tests that run
/// concurrently (Swift Testing's default) never see each other's stubbed
/// response or recorded request. Every test that uses this should give its
/// stub client a unique host (see `makeStubbedClient`).
nonisolated final class URLProtocolStubRegistry {
    static let shared = URLProtocolStubRegistry()

    private let lock = NSLock()
    private var responses: [String: StubbedResponse] = [:]
    private var recorded: [String: RecordedRequest] = [:]

    private init() {}

    func setResponse(_ response: StubbedResponse, forHost host: String) {
        lock.lock()
        responses[host] = response
        lock.unlock()
    }

    func response(forHost host: String) -> StubbedResponse? {
        lock.lock()
        defer { lock.unlock() }
        return responses[host]
    }

    func record(_ request: RecordedRequest, forHost host: String) {
        lock.lock()
        recorded[host] = request
        lock.unlock()
    }

    func recordedRequest(forHost host: String) -> RecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return recorded[host]
    }
}

nonisolated final class URLProtocolStub: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        var headers: [String: String] = [:]
        request.allHTTPHeaderFields?.forEach { headers[$0] = $1 }
        let body = request.httpBody ?? Self.readBody(from: request.httpBodyStream)

        URLProtocolStubRegistry.shared.record(
            RecordedRequest(url: url, httpMethod: request.httpMethod ?? "GET", headers: headers, body: body),
            forHost: host
        )

        guard let stub = URLProtocolStubRegistry.shared.response(forHost: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` frequently moves `httpBody` into a stream by the time the
    /// protocol sees the request, so the body has to be read from there too.
    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Builds a `RommAPIClient` wired to a fresh, uniquely-hosted stub session,
/// plus the host to configure the response for and read the recorded request
/// back from. A unique host per call keeps parallel tests independent without
/// any shared mutable state between them.
func makeStubbedClient(file: StaticString = #filePath, line: UInt = #line) -> (client: RommAPIClient, host: String) {
    let host = "stub-\(UUID().uuidString.lowercased()).romm.test"
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: configuration)
    let tokenProvider = SaveSyncStubTokenProvider(serverURL: "https://\(host)")
    let client = RommAPIClient(tokenProvider: tokenProvider, urlSession: session)
    return (client, host)
}

/// Minimal `PTokenProvider` that authenticates with a fixed client token, so
/// `RommAPIClient` never touches Keychain/UserDefaults during a test.
struct SaveSyncStubTokenProvider: PTokenProvider {
    let serverURL: String

    func getAuthToken() -> String? { "stub-token" }
    func getServerURL() -> String? { serverURL }
    func getUsername() -> String? { nil }
    func getPassword() -> String? { nil }
    func isConfigured() -> Bool { true }
    func getAuthMethod() -> AuthMethod { .clientToken }
    func getClientToken() -> String? { "rmm_stub_token" }
    func getClientTokenInfo() -> ClientTokenInfo? { nil }
    func hasScope(_ scope: String) -> Bool { true }
    var availableScopes: [String]? { nil }
}
