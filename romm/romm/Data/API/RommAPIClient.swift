//
//  RommAPIClient.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation
import os

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

protocol PRommAPIClient {
    func makeRequest<T: Codable>(path: String, method: HTTPMethod, body: Data?, responseType: T.Type) async throws -> T
    func makeRequest(path: String, method: HTTPMethod, body: Data?) async throws -> Data
    func downloadFile(path: String, progressHandler: ((Int64, Int64) -> Void)?) async throws -> URL
    func multipartRequest(path: String, method: HTTPMethod, boundary: String, formData: Data, additionalHeaders: [String: String]?) async throws -> Data
    func get<T: Codable>(_ path: String, responseType: T.Type) async throws -> T
    func get(_ path: String) async throws -> Data
    func getBinary(_ path: String) async throws -> Data
    func post<RequestBody: Codable, ResponseType: Codable>(_ path: String, body: RequestBody, responseType: ResponseType.Type) async throws -> ResponseType
    func post(_ path: String, body: Data?) async throws -> Data
    func put<RequestBody: Codable, ResponseType: Codable>(_ path: String, body: RequestBody, responseType: ResponseType.Type) async throws -> ResponseType
    func put<RequestBody: Codable>(_ path: String, body: RequestBody) async throws -> Data
    func put(_ path: String, body: Data?) async throws -> Data
    func delete(_ path: String) async throws -> Data
    func getRomManual(romId: Int) async throws -> Manual?
    func getManualPDFData(manualURL: String) async throws -> Data
    func getRomDetails(id: Int) async throws -> DetailedRomSchema

    // ROM API Wrapper methods
    func getRoms(
        searchTerm: String?,
        platformId: Int?,
        limit: Int
    ) async throws -> CustomLimitOffsetPageSimpleRomSchema

    func getRomsWithFilters(
        searchTerm: String?,
        platformId: Int?,
        collectionId: Int?,
        limit: Int,
        offset: Int?,
        withCharIndex: Bool?,
        orderBy: String?,
        orderDir: String?,
        filters: RomFilters
    ) async throws -> CustomLimitOffsetPageSimpleRomSchema

    // ROM Search API Wrapper methods
    func searchRomsWithOpenAPI(query: String) async throws -> CustomLimitOffsetPageSimpleRomSchema

    // Collections API Wrapper methods
    func getCollections(limit: Int?, offset: Int?) async throws -> [CollectionSchema]
    func getCollection(id: Int) async throws -> CollectionSchema
    func getVirtualCollections(type: String, limit: Int?) async throws -> [VirtualCollectionSchema]
    func getVirtualCollection(id: String) async throws -> VirtualCollectionSchema
    func createCollection(name: String, description: String, isPublic: Bool, artwork: URL?) async throws -> CollectionSchema
    func updateCollection(id: Int, name: String, description: String, isPublic: Bool, romIds: [Int]?, artwork: URL?) async throws -> CollectionSchema
    func deleteCollection(id: Int) async throws -> String

    // Platforms API Wrapper methods
    func getPlatforms() async throws -> [PlatformSchema]
    func addPlatform(name: String, slug: String) async throws -> PlatformSchema
    func deletePlatform(id: Int) async throws -> String

    // Firmware API Wrapper methods
    func getPlatformFirmware(platformId: Int) async throws -> [FirmwareSchema]
    func downloadFirmwareContent(id: Int, fileName: String) async throws -> Data

    // Heartbeat API Wrapper methods
    func getHeartbeat() async throws -> HeartbeatResponse
    func getHeartbeat(from serverURL: String) async throws -> HeartbeatResponse

    // ROM user props
    func updateRomLastPlayed(id: Int) async throws -> RomUserSchema

    // Stats, Saves, States
    func getStats() async throws -> StatsReturn
    func getSaves(romId: Int) async throws -> [SaveSchema]
    func getStates(romId: Int) async throws -> [StateSchema]

    // Saves sync
    func uploadSave(romId: Int, emulator: String?, slot: String?, deviceId: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
    func updateSave(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
    func downloadSave(id: Int, deviceId: String?) async throws -> Data
    func deleteSaves(ids: [Int]) async throws

    // States sync
    func uploadState(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema
    func updateState(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema
    func downloadState(id: Int) async throws -> Data
    func deleteStates(ids: [Int]) async throws
}

enum APIClientError: LocalizedError {
    case noConfiguration
    case noCredentials
    case invalidURL(String)
    case authenticationRequired
    case networkError(Error)
    case invalidResponse(Int, String)
    case decodingError(Error)
    case cloudflareProtection(String)

    var errorDescription: String? {
        switch self {
        case .noConfiguration:
            return "No configuration found - please complete setup"
        case .noCredentials:
            return "No authentication credentials found - please setup login"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .authenticationRequired:
            return "Authentication required - please check credentials"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let error):
            return "Data decoding error: \(error.localizedDescription)"
        case .cloudflareProtection(let details):
            return "Server is protected by Cloudflare - browser authentication required"
        }
    }
}

// MARK: - Core Client

class RommAPIClient: PRommAPIClient {
    static let shared = RommAPIClient()

    let tokenProvider: PTokenProvider
    let urlSession: URLSession
    let logger = Logger.network
    private let sessionDelegate = PrivateNetworkURLSessionDelegate()

    init(tokenProvider: PTokenProvider = TokenProvider(),
         urlSession: URLSession? = nil) {
        self.tokenProvider = tokenProvider

        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0
            configuration.timeoutIntervalForResource = 60 * 60
            configuration.waitsForConnectivity = true
            configuration.allowsCellularAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            configuration.allowsConstrainedNetworkAccess = true
            self.urlSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        }
    }

    // No-op after OpenAPI removal – credentials are read fresh on each request
    func invalidateConfiguration() {}

    // MARK: - makeRequest (generic)

    func makeRequest<T: Codable>(path: String, method: HTTPMethod, body: Data? = nil, responseType: T.Type) async throws -> T {
        let data = try await makeRequest(path: path, method: method, body: body)
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            let responsePreview = String(data: data.prefix(200), encoding: .utf8) ?? "Binary data"
            logger.error("Decoding error for \(responseType) at path \(path): \(error)")
            logger.error("Response data preview: \(responsePreview)")
            throw APIClientError.decodingError(error)
        }
    }

    // MARK: - makeRequest (raw Data)

    func makeRequest(path: String, method: HTTPMethod, body: Data? = nil) async throws -> Data {
        let measurement = PerformanceMeasurement(operation: "\(method.rawValue) \(path)")
        logger.logNetworkRequest(method: method.rawValue, url: path)

        let url = try buildURL(path: path)
        let authHeader = try makeAuthHeader()

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0

        if let body {
            request.httpBody = body
            logger.debug("Request body size: \(body.count) bytes")
        }

        logger.info("Request URL: \(url.absoluteString)")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type")
                throw APIClientError.networkError(URLError(.badServerResponse))
            }

            logger.logNetworkRequest(method: method.rawValue, url: path, statusCode: httpResponse.statusCode)
            logger.debug("Response data size: \(data.count) bytes")

            switch httpResponse.statusCode {
            case 200...299:
                measurement.end()
                return data
            case 401:
                logger.warning("Authentication failed - invalid credentials")
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIClientError.authenticationRequired
            case 403:
                let msg = String(data: data, encoding: .utf8) ?? "Forbidden"

                // Check if this is a Cloudflare challenge
                if isCloudflareChallenge(response: httpResponse, body: msg) {
                    logger.warning("Cloudflare protection detected")
                    throw APIClientError.cloudflareProtection(msg)
                }

                // For client token auth, 403 means token was revoked/invalid
                if tokenProvider.getAuthMethod() == .clientToken {
                    logger.warning("Client token rejected (403) - session expired")
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                    throw APIClientError.authenticationRequired
                }

                // Regular 403 error
                logger.error("Forbidden (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            case 400...499:
                let msg = String(data: data, encoding: .utf8) ?? "Client error"
                logger.error("Client error (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            case 500...599:
                let msg = String(data: data, encoding: .utf8) ?? "Server error"
                logger.error("Server error (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            default:
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("Unexpected status (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            }
        } catch let error as URLError {
            logger.logNetworkError(method: method.rawValue, url: path, error: error)
            
            // Check if this might be a Cloudflare issue based on error type
            if error.code == .networkConnectionLost || 
               error.code == .cannotConnectToHost ||
               error.code == .notConnectedToInternet {
                logger.warning("⚠️ Connection error that might indicate Cloudflare protection: \(error.code)")
            }
            
            throw APIClientError.networkError(error)
        } catch let error as APIClientError {
            throw error
        } catch {
            logger.logNetworkError(method: method.rawValue, url: path, error: error)
            throw APIClientError.networkError(error)
        }
    }

    // MARK: - downloadFile

    func downloadFile(path: String, progressHandler: ((Int64, Int64) -> Void)? = nil) async throws -> URL {
        let measurement = PerformanceMeasurement(operation: "DOWNLOAD \(path)")
        logger.logNetworkRequest(method: HTTPMethod.get.rawValue, url: path)

        let url = try buildURL(path: path)
        let authHeader = try makeAuthHeader()

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60.0

        logger.debug("Download URL: \(url.absoluteString)")
        #if DEBUG
        logger.debug("Download Auth header (debug-only): \(authHeader)")
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            var progressObservation: NSKeyValueObservation?
            var downloadTask: URLSessionDownloadTask?

            downloadTask = urlSession.downloadTask(with: request) { [weak self] tempURL, response, error in
                progressObservation?.invalidate()

                if let error = error as? URLError {
                    self?.logger.logNetworkError(method: HTTPMethod.get.rawValue, url: path, error: error)
                    continuation.resume(throwing: APIClientError.networkError(error))
                    return
                }

                if let error {
                    self?.logger.logNetworkError(method: HTTPMethod.get.rawValue, url: path, error: error)
                    continuation.resume(throwing: APIClientError.networkError(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.logger.error("Invalid download response type")
                    continuation.resume(throwing: APIClientError.networkError(URLError(.badServerResponse)))
                    return
                }

                self?.logger.logNetworkRequest(method: HTTPMethod.get.rawValue, url: path, statusCode: httpResponse.statusCode)
                let headerKeys = ["Content-Length", "Content-Type", "Content-Encoding", "Transfer-Encoding", "Location", "Server", "X-Accel-Redirect"]
                let headerDump = headerKeys.compactMap { key -> String? in
                    guard let value = httpResponse.value(forHTTPHeaderField: key) else { return nil }
                    return "\(key)=\(value)"
                }.joined(separator: " | ")
                self?.logger.info("Download response headers: \(headerDump)")
                if let tempURL,
                   let data = try? Data(contentsOf: tempURL) {
                    self?.logger.info("Download body bytes received: \(data.count)")
                    if data.count <= 512, let body = String(data: data, encoding: .utf8) {
                        self?.logger.info("Download body preview: \(body)")
                    }
                }

                switch httpResponse.statusCode {
                case 200...299:
                    guard let tempURL else {
                        self?.logger.error("Download completed without temporary file")
                        continuation.resume(throwing: APIClientError.networkError(URLError(.cannotCreateFile)))
                        return
                    }
                    // Move temp file to a persistent location BEFORE the handler returns —
                    // iOS deletes the URLSession temp file as soon as this handler exits.
                    // The URLSession temp file carries no meaningful extension, so derive it
                    // from the Content-Disposition filename (falling back to the requested
                    // path, then the temp file) to preserve e.g. `.zip` for archive ROMs.
                    let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
                    let fileExtension = DownloadFilename.fileExtension(
                        contentDisposition: contentDisposition,
                        requestedPath: path,
                        tempURL: tempURL
                    )
                    var persistentURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    if !fileExtension.isEmpty {
                        persistentURL.appendPathExtension(fileExtension)
                    }
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: persistentURL)
                    } catch {
                        self?.logger.error("Failed to persist download temp file: \(error)")
                        continuation.resume(throwing: APIClientError.networkError(URLError(.cannotCreateFile)))
                        return
                    }
                    let downloadedBytes = downloadTask?.progress.completedUnitCount ?? 0
                    let totalBytes = downloadTask?.progress.totalUnitCount ?? 0
                    let normalizedTotal = totalBytes > 0 ? totalBytes : downloadedBytes
                    progressHandler?(downloadedBytes, normalizedTotal)
                    measurement.end()
                    continuation.resume(returning: persistentURL)

                case 401:
                    self?.logger.warning("Authentication failed during download")
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                    continuation.resume(throwing: APIClientError.authenticationRequired)

                case 400...599:
                    let message: String
                    if let tempURL,
                       let data = try? Data(contentsOf: tempURL),
                       let serverMessage = String(data: data.prefix(500), encoding: .utf8),
                       !serverMessage.isEmpty {
                        message = serverMessage
                    } else {
                        message = "Download request failed"
                    }
                    self?.logger.error("Download failed (\(httpResponse.statusCode)): \(message)")
                    continuation.resume(throwing: APIClientError.invalidResponse(httpResponse.statusCode, message))

                default:
                    let message = "Unexpected status code: \(httpResponse.statusCode)"
                    self?.logger.error(message)
                    continuation.resume(throwing: APIClientError.invalidResponse(httpResponse.statusCode, message))
                }
            }

            guard let downloadTask else {
                continuation.resume(throwing: APIClientError.networkError(URLError(.unknown)))
                return
            }

            progressObservation = downloadTask.progress.observe(\.completedUnitCount, options: [.new]) { progress, _ in
                let downloadedBytes = progress.completedUnitCount
                let totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : 0
                progressHandler?(downloadedBytes, totalBytes)
            }

            downloadTask.resume()
        }
    }

    // MARK: - multipartRequest

    func multipartRequest(
        path: String,
        method: HTTPMethod,
        boundary: String,
        formData: Data,
        additionalHeaders: [String: String]? = nil
    ) async throws -> Data {
        let measurement = PerformanceMeasurement(operation: "\(method.rawValue) \(path) [multipart]")
        logger.logNetworkRequest(method: method.rawValue, url: path)

        let url = try buildURL(path: path)
        let authHeader = try makeAuthHeader()

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60.0
        additionalHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = formData

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid multipart response type")
                throw APIClientError.networkError(URLError(.badServerResponse))
            }

            logger.logNetworkRequest(method: method.rawValue, url: path, statusCode: httpResponse.statusCode)

            switch httpResponse.statusCode {
            case 200...299:
                measurement.end()
                return data
            case 401:
                logger.warning("Authentication failed for multipart request")
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIClientError.authenticationRequired
            case 403:
                let msg = String(data: data, encoding: .utf8) ?? "Forbidden"

                if isCloudflareChallenge(response: httpResponse, body: msg) {
                    logger.warning("Cloudflare protection detected on multipart request")
                    throw APIClientError.cloudflareProtection(msg)
                }

                if tokenProvider.getAuthMethod() == .clientToken {
                    logger.warning("Client token rejected (403) on multipart - session expired")
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                    throw APIClientError.authenticationRequired
                }

                logger.error("Multipart forbidden (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            case 400...499:
                let msg = String(data: data, encoding: .utf8) ?? "Client error"
                logger.error("Multipart client error (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            case 500...599:
                let msg = String(data: data, encoding: .utf8) ?? "Server error"
                logger.error("Multipart server error (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            default:
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("Multipart unexpected status (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            }
        } catch let error as URLError {
            logger.logNetworkError(method: method.rawValue, url: path, error: error)
            throw APIClientError.networkError(error)
        } catch let error as APIClientError {
            throw error
        } catch {
            logger.logNetworkError(method: method.rawValue, url: path, error: error)
            throw APIClientError.networkError(error)
        }
    }

    // MARK: - Convenience Methods

    func get<T: Codable>(_ path: String, responseType: T.Type) async throws -> T {
        try await makeRequest(path: path, method: .get, responseType: responseType)
    }

    func get(_ path: String) async throws -> Data {
        try await makeRequest(path: path, method: .get)
    }

    func getBinary(_ path: String) async throws -> Data {
        let url = try buildURL(path: path)
        let authHeader = try makeAuthHeader()
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.networkError(URLError(.badServerResponse)) }
        switch http.statusCode {
        case 200...299: return data
        case 401:
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
            throw APIClientError.authenticationRequired
        default:
            let msg = String(data: data.prefix(500), encoding: .utf8) ?? "Error"
            throw APIClientError.invalidResponse(http.statusCode, msg)
        }
    }

    func post<RequestBody: Codable, ResponseType: Codable>(
        _ path: String,
        body: RequestBody,
        responseType: ResponseType.Type
    ) async throws -> ResponseType {
        let jsonData = try JSONEncoder().encode(body)
        return try await makeRequest(path: path, method: .post, body: jsonData, responseType: responseType)
    }

    func post(_ path: String, body: Data? = nil) async throws -> Data {
        try await makeRequest(path: path, method: .post, body: body)
    }

    func put<RequestBody: Codable, ResponseType: Codable>(
        _ path: String,
        body: RequestBody,
        responseType: ResponseType.Type
    ) async throws -> ResponseType {
        let jsonData = try JSONEncoder().encode(body)
        return try await makeRequest(path: path, method: .put, body: jsonData, responseType: responseType)
    }

    func put<RequestBody: Codable>(_ path: String, body: RequestBody) async throws -> Data {
        let jsonData = try JSONEncoder().encode(body)
        return try await makeRequest(path: path, method: .put, body: jsonData)
    }

    func put(_ path: String, body: Data? = nil) async throws -> Data {
        try await makeRequest(path: path, method: .put, body: body)
    }

    func delete(_ path: String) async throws -> Data {
        try await makeRequest(path: path, method: .delete)
    }

    // MARK: - Internal Helpers

    func buildURL(path: String) throws -> URL {
        guard let serverURL = tokenProvider.getServerURL() else {
            logger.error("No server URL configured")
            throw APIClientError.noConfiguration
        }
        let cleanServerURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullURLString = "\(cleanServerURL)/\(cleanPath)"
        guard let url = URL(string: fullURLString) else {
            logger.error("Invalid URL: \(fullURLString)")
            throw APIClientError.invalidURL(fullURLString)
        }
        return url
    }

    func makeAuthHeader() throws -> String {
        let authMethod = tokenProvider.getAuthMethod()
        switch authMethod {
        case .clientToken:
            guard let token = tokenProvider.getClientToken() else {
                logger.error("No client token available")
                throw APIClientError.noCredentials
            }
            return "Bearer \(token)"
        case .classic:
            guard let username = tokenProvider.getUsername(),
                  let password = tokenProvider.getPassword() else {
                logger.error("No authentication credentials available")
                throw APIClientError.noCredentials
            }
            let loginString = "\(username):\(password)"
            guard let loginData = loginString.data(using: .utf8) else {
                logger.error("Failed to encode credentials")
                throw APIClientError.authenticationRequired
            }
            return "Basic \(loginData.base64EncodedString())"
        }
    }

    func withQuery(_ path: String, _ params: [(String, String?)]) -> String {
        let parts = params.compactMap { key, value -> String? in
            guard let value else { return nil }
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }
        guard !parts.isEmpty else { return path }
        return "\(path)?\(parts.joined(separator: "&"))"
    }

    // MARK: - Cloudflare Detection

    func isCloudflareChallenge(response: HTTPURLResponse, body: String) -> Bool {
        // Check for Cloudflare-specific headers
        let hasCFHeaders = response.allHeaderFields.keys.contains { key in
            guard let headerName = key as? String else { return false }
            return headerName.lowercased().starts(with: "cf-")
        }

        // Check server header
        let serverHeader = (response.allHeaderFields["Server"] as? String)?.lowercased()
        let isCloudflareServer = serverHeader?.contains("cloudflare") == true

        // Check body content for Cloudflare challenge page markers
        let bodyLower = body.lowercased()
        let hasChallengePage = bodyLower.contains("just a moment") ||
                              bodyLower.contains("checking your browser") ||
                              bodyLower.contains("challenge-platform") ||
                              bodyLower.contains("cf-browser-verification") ||
                              (bodyLower.contains("<!doctype html>") && hasCFHeaders)

        let isCloudflare = (hasCFHeaders || isCloudflareServer) && hasChallengePage

        if isCloudflare {
            logger.warning("🔒 Cloudflare challenge detected!")
            logger.debug("CF Headers: \(hasCFHeaders), CF Server: \(isCloudflareServer), Challenge Page: \(hasChallengePage)")
        }

        return isCloudflare
    }

}
