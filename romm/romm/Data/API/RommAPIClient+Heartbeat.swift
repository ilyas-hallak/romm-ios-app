//
//  RommAPIClient+Heartbeat.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

// MARK: - Heartbeat API Wrapper
extension RommAPIClient {

    /// Own session for the reachability check during setup.
    ///
    /// The shared session allows an hour per resource, which is right for a ROM
    /// download and wrong here: a mistyped or unreachable address does not fail,
    /// it just never answers, and the user watches a spinner until they give up.
    /// A short, self-contained budget turns that into an error message.
    private static let setupSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = RommAPIClient.setupTimeout
        configuration.timeoutIntervalForResource = RommAPIClient.setupTimeout
        // Queueing the request until the network looks better would bring the
        // endless spinner back in another shape.
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Long enough for a slow home server behind a proxy, short enough that
    /// nobody wonders whether the app is still doing anything.
    private static let setupTimeout: TimeInterval = 15

    func getHeartbeat() async throws -> HeartbeatResponse {
        return try await get("api/heartbeat", responseType: HeartbeatResponse.self)
    }

    /// Get heartbeat from a specific server URL (for setup flow before login)
    func getHeartbeat(from serverURL: String) async throws -> HeartbeatResponse {
        let cleanURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanURL)/api/heartbeat") else {
            throw APIClientError.invalidURL("\(cleanURL)/api/heartbeat")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.setupTimeout

        logger.info("🔍 [Network] - Fetching heartbeat from: \(url.absoluteString)")

        do {
            let (data, response) = try await Self.setupSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type for heartbeat")
                throw APIClientError.networkError(URLError(.badServerResponse))
            }

            logger.info("📊 [Network] - Heartbeat response status: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                // Success - decode response
                do {
                    let heartbeat = try JSONDecoder().decode(HeartbeatResponse.self, from: data)
                    logger.info("✅ [Network] - Heartbeat successful: v\(heartbeat.SYSTEM.VERSION)")
                    return heartbeat
                } catch {
                    let preview = String(data: data.prefix(500), encoding: .utf8) ?? "binary data"
                    logger.error("Failed to decode heartbeat response: \(error)")
                    logger.error("Raw response (first 500 chars): \(preview)")
                    throw APIClientError.decodingError(error)
                }
                
            case 403:
                let msg = String(data: data, encoding: .utf8) ?? "Forbidden"
                logger.warning("⚠️ [Network] - 403 response received, checking for Cloudflare...")
                
                // Check if this is a Cloudflare challenge
                if isCloudflareChallenge(response: httpResponse, body: msg) {
                    logger.warning("🔒 [Network] - Cloudflare protection detected!")
                    throw APIClientError.cloudflareProtection(msg)
                }
                
                // Regular 403
                logger.error("❌ [Network] - Forbidden (not Cloudflare): \(msg.prefix(200))")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
                
            case 401:
                logger.warning("⚠️ [Network] - Authentication required for heartbeat")
                throw APIClientError.authenticationRequired
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("❌ [Network] - Unexpected status \(httpResponse.statusCode): \(errorMessage.prefix(200))")
                throw APIClientError.invalidResponse(httpResponse.statusCode, errorMessage)
            }
            
        } catch let error as APIClientError {
            // Re-throw API client errors
            throw error
        } catch let urlError as URLError {
            logger.error("❌ [Network] - URLError during heartbeat: \(urlError.code.rawValue) - \(urlError.localizedDescription)")
            
            // Log specific error codes that might indicate Cloudflare issues
            if urlError.code == .networkConnectionLost ||
               urlError.code == .cannotConnectToHost ||
               urlError.code == .notConnectedToInternet {
                logger.warning("⚠️ This might be a Cloudflare protection issue")
            }
            
            throw APIClientError.networkError(urlError)
        } catch {
            logger.error("❌ [Network] - Unexpected error during heartbeat: \(error)")
            throw APIClientError.networkError(error)
        }
    }
}
