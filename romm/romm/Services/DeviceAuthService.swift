//
//  DeviceAuthService.swift
//  romm
//
//  Drives the RomM device-authorization pairing flow: start a request, let the
//  user approve it in the browser, then poll until the server hands back a token.
//
//  The resulting token is a bound client token, so callers persist it via
//  `ClientTokenAuthService` and switch the app to `.clientToken` auth.
//

import Foundation
import UIKit

final class DeviceAuthService {

    private let logger = Logger.auth

    /// Client identifier string reported to the server.
    static let clientName = "romm-ios"

    /// Scopes the app requests. Read access across the library plus the writes we
    /// actually perform (save/state assets, user-rom props, device registration).
    static let defaultScopes: [String] = [
        "me.read",
        "roms.read",
        "platforms.read",
        "assets.read",
        "assets.write",
        "devices.read",
        "devices.write",
        "roms.user.read",
        "roms.user.write",
        "collections.read",
        "firmware.read"
    ]

    private let deviceIdentifierKey = "auth.clientDeviceIdentifier"

    // MARK: - Stable device identifier

    /// A UUID that stays the same across launches so the server can recognize this
    /// install (and so re-pairing reuses the same device row).
    func clientDeviceIdentifier() -> String {
        if let stored = UserDefaults.standard.string(forKey: deviceIdentifierKey) {
            return stored
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: deviceIdentifierKey)
        return generated
    }

    /// The device name shown on the approval screen (e.g. "Ilyas' iPhone").
    /// `UIDevice.current` is main-actor isolated under strict concurrency.
    @MainActor
    private static func deviceName() -> String {
        UIDevice.current.name
    }

    // MARK: - Session

    private func makeSession() -> URLSession {
        URLSession(
            configuration: .default,
            delegate: PrivateNetworkURLSessionDelegate(),
            delegateQueue: nil
        )
    }

    private func cleanBaseURL(_ serverURL: String) -> String {
        serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Step 1: init

    /// Starts a new pairing request. Returns the codes and the verification path.
    func initPairing(serverURL: String, scopes: [String] = DeviceAuthService.defaultScopes) async throws -> DeviceAuthInitResponse {
        let base = cleanBaseURL(serverURL)
        guard let url = URL(string: "\(base)/api/auth/device/init") else {
            throw DeviceAuthError.invalidURL
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        let payload = DeviceAuthInitRequest(
            clientDeviceIdentifier: clientDeviceIdentifier(),
            name: await Self.deviceName(),
            client: Self.clientName,
            platform: "ios",
            clientVersion: appVersion,
            requestedScopes: scopes
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20.0
        request.httpBody = try JSONEncoder().encode(payload)

        logger.info("Starting device pairing request")

        let (data, response) = try await makeSession().data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeviceAuthError.network("Invalid response from server")
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "non-utf8"
            logger.error("device/init failed HTTP \(http.statusCode): \(body)")
            throw DeviceAuthError.network("Server rejected the pairing request (HTTP \(http.statusCode)).")
        }

        do {
            let decoded = try JSONDecoder().decode(DeviceAuthInitResponse.self, from: data)
            logger.info("Device pairing started (user_code present, expires in \(decoded.expiresIn)s)")
            return decoded
        } catch {
            logger.error("Failed to decode device/init response: \(error)")
            throw DeviceAuthError.network("The server returned an unexpected pairing response.")
        }
    }

    /// Builds the absolute URL the user opens in the browser to approve pairing.
    func verificationURL(serverURL: String, init response: DeviceAuthInitResponse) -> URL? {
        let base = cleanBaseURL(serverURL)
        return URL(string: "\(base)\(response.verificationPathComplete)")
    }

    // MARK: - Step 3: poll

    /// Polls the token endpoint until the request is approved, denied, or expires.
    /// Respects the server-provided `interval` and honours `slow_down`.
    /// Cancellable via the enclosing `Task` (surfaces as `DeviceAuthError.cancelled`).
    func pollForToken(serverURL: String, init response: DeviceAuthInitResponse) async throws -> DeviceAuthTokenResponse {
        let base = cleanBaseURL(serverURL)
        guard let url = URL(string: "\(base)/api/auth/device/token") else {
            throw DeviceAuthError.invalidURL
        }

        let session = makeSession()
        let payload = try JSONEncoder().encode(DeviceAuthTokenRequest(deviceCode: response.deviceCode))
        var interval = max(response.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(response.expiresIn))

        while true {
            if Task.isCancelled { throw DeviceAuthError.cancelled }
            if Date() >= deadline { throw DeviceAuthError.expired }

            do {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } catch {
                throw DeviceAuthError.cancelled
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20.0
            request.httpBody = payload

            let data: Data
            let response2: URLResponse
            do {
                (data, response2) = try await session.data(for: request)
            } catch {
                if Task.isCancelled { throw DeviceAuthError.cancelled }
                // Transient network blip while polling — keep trying until the deadline.
                logger.debug("device/token poll transient error: \(error.localizedDescription)")
                continue
            }

            guard let http = response2 as? HTTPURLResponse else {
                continue
            }

            if (200...299).contains(http.statusCode) {
                do {
                    let token = try JSONDecoder().decode(DeviceAuthTokenResponse.self, from: data)
                    logger.info("Device pairing approved — token received (\(token.scopes.count) scopes)")
                    return token
                } catch {
                    logger.error("Failed to decode device/token success: \(error)")
                    throw DeviceAuthError.network("The server returned an unexpected token response.")
                }
            }

            // Non-2xx: inspect the OAuth `detail` code.
            let detail = Self.detailCode(from: data)
            switch DeviceAuthPollStatus(detail: detail ?? "") {
            case .pending:
                continue
            case .slowDown:
                interval += 5
                continue
            case .denied:
                throw DeviceAuthError.denied
            case .expired:
                throw DeviceAuthError.expired
            case nil:
                logger.error("device/token unexpected HTTP \(http.statusCode) detail=\(detail ?? "nil")")
                throw DeviceAuthError.network("Sign-in failed (HTTP \(http.statusCode)).")
            }
        }
    }

    private static func detailCode(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let detail = json["detail"] as? String { return detail }
        if let error = json["error"] as? String { return error }
        return nil
    }
}
