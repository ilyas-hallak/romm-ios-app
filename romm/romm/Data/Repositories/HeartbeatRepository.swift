//
//  HeartbeatRepository.swift
//  romm
//

import Foundation

class HeartbeatRepository: PHeartbeatRepository {
    private let logger = Logger.data
    private let apiClient: RommAPIClient
    private let userDefaults: UserDefaults

    // MARK: - Constants

    let minSupportedServerVersion = "4.1.0"
    let maxSupportedServerVersion = "4.9.0"
    let versionCheckThrottleSeconds: TimeInterval = 30

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastKnownServerVersion = "heartbeat.lastKnownServerVersion"
        static let lastVersionCheckTime = "heartbeat.lastVersionCheckTime"
    }

    // MARK: - Init

    init(
        apiClient: RommAPIClient = RommAPIClient.shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
    }

    // MARK: - Fetch Heartbeat

    func getHeartbeat() async throws -> Heartbeat {
        logger.info("Getting heartbeat from API...")

        do {
            let response = try await apiClient.getHeartbeat()
            let heartbeat = Heartbeat(version: response.SYSTEM.VERSION)
            logger.info("Retrieved server version: \(heartbeat.version)")
            return heartbeat
        } catch let error as APIClientError {
            logger.error("Error getting heartbeat: \(error)")
            if case .decodingError = error {
                throw HeartbeatError.decodingError(error)
            }
            throw HeartbeatError.networkError(error)
        } catch {
            logger.error("Error getting heartbeat: \(error)")
            throw HeartbeatError.networkError(error)
        }
    }

    func getHeartbeat(from serverURL: String) async throws -> Heartbeat {
        logger.info("Getting heartbeat from URL: \(serverURL)")

        do {
            let response = try await apiClient.getHeartbeat(from: serverURL)
            let heartbeat = Heartbeat(version: response.SYSTEM.VERSION)
            logger.info("Retrieved server version from URL: \(heartbeat.version)")
            return heartbeat
        } catch let error as APIClientError {
            logger.error("Error getting heartbeat from URL: \(error)")
            if case .decodingError = error {
                throw HeartbeatError.decodingError(error)
            }
            throw HeartbeatError.networkError(error)
        } catch {
            logger.error("Error getting heartbeat from URL: \(error)")
            throw HeartbeatError.networkError(error)
        }
    }

    // MARK: - Check Server Version

    func checkServerVersion() async throws -> Heartbeat {
        let heartbeat = try await getHeartbeat()
        let serverVersion = heartbeat.version

        // Check if version changed since last known
        if let lastKnown = getLastKnownServerVersion(), lastKnown != serverVersion {
            logger.warning("Server version changed from \(lastKnown) to \(serverVersion)")
            throw HeartbeatError.serverVersionChanged(from: lastKnown, to: serverVersion)
        }

        // Check if version is below minimum
        if compareVersions(serverVersion, minSupportedServerVersion) < 0 {
            logger.warning(
                "Server version \(serverVersion) is below minimum \(minSupportedServerVersion)")
            throw HeartbeatError.serverVersionTooLow(
                serverVersion: serverVersion,
                minRequired: minSupportedServerVersion
            )
        }

        // Check if version is above maximum
        if compareVersions(serverVersion, maxSupportedServerVersion) > 0 {
            logger.warning(
                "Server version \(serverVersion) is above maximum \(maxSupportedServerVersion)")
            throw HeartbeatError.serverVersionTooHigh(
                serverVersion: serverVersion,
                maxSupported: maxSupportedServerVersion
            )
        }

        // Update stored version
        saveServerVersion(serverVersion)
        logger.info("Server version check passed: \(serverVersion)")

        return heartbeat
    }

    func checkServerVersion(allowIncompatibleVersion: Bool) async throws -> Heartbeat {
        let heartbeat = try await getHeartbeat()
        let serverVersion = heartbeat.version

        // Check if version changed since last known
        if let lastKnown = getLastKnownServerVersion(), lastKnown != serverVersion {
            logger.warning("Server version changed from \(lastKnown) to \(serverVersion)")
            throw HeartbeatError.serverVersionChanged(from: lastKnown, to: serverVersion)
        }

        // If user allowed incompatible versions, only check minimum (not maximum)
        if allowIncompatibleVersion {
            logger.info("Incompatible version login allowed - skipping maximum version check")

            // Only check minimum version (critical incompatibility)
            if compareVersions(serverVersion, minSupportedServerVersion) < 0 {
                logger.warning(
                    "Server version \(serverVersion) is below minimum \(minSupportedServerVersion)")
                throw HeartbeatError.serverVersionTooLow(
                    serverVersion: serverVersion,
                    minRequired: minSupportedServerVersion
                )
            }
        } else {
            // Standard checks for both minimum and maximum
            if compareVersions(serverVersion, minSupportedServerVersion) < 0 {
                logger.warning(
                    "Server version \(serverVersion) is below minimum \(minSupportedServerVersion)")
                throw HeartbeatError.serverVersionTooLow(
                    serverVersion: serverVersion,
                    minRequired: minSupportedServerVersion
                )
            }

            if compareVersions(serverVersion, maxSupportedServerVersion) > 0 {
                logger.warning(
                    "Server version \(serverVersion) is above maximum \(maxSupportedServerVersion)")
                throw HeartbeatError.serverVersionTooHigh(
                    serverVersion: serverVersion,
                    maxSupported: maxSupportedServerVersion
                )
            }
        }

        // Update stored version
        saveServerVersion(serverVersion)
        logger.info("Server version check passed: \(serverVersion)")

        return heartbeat
    }

    // MARK: - Storage

    func getLastKnownServerVersion() -> String? {
        userDefaults.string(forKey: Keys.lastKnownServerVersion)
    }

    func getLastVersionCheckTime() -> Date? {
        userDefaults.object(forKey: Keys.lastVersionCheckTime) as? Date
    }

    func saveServerVersion(_ version: String) {
        userDefaults.set(version, forKey: Keys.lastKnownServerVersion)
        userDefaults.set(Date(), forKey: Keys.lastVersionCheckTime)
        logger.debug("Saved server version: \(version)")
    }

    func clearServerVersion() {
        userDefaults.removeObject(forKey: Keys.lastKnownServerVersion)
        userDefaults.removeObject(forKey: Keys.lastVersionCheckTime)
        logger.debug("Cleared stored server version")
    }

    // MARK: - Throttling

    func shouldThrottleVersionCheck() -> Bool {
        guard let lastCheck = getLastVersionCheckTime() else {
            return false
        }
        let elapsed = Date().timeIntervalSince(lastCheck)
        return elapsed < versionCheckThrottleSeconds
    }

    // MARK: - Version Comparison

    func isVersionCompatible(_ version: String) -> Bool {
        let aboveMin = compareVersions(version, minSupportedServerVersion) >= 0
        let belowMax = compareVersions(version, maxSupportedServerVersion) <= 0
        return aboveMin && belowMax
    }

    private func compareVersions(_ version1: String, _ version2: String) -> Int {
        // "development" builds are treated as above any release version
        if version1 == "development" { return 1 }
        if version2 == "development" { return -1 }

        // Strip pre-release suffixes (e.g. "4.8.0-alpha.1" → "4.8.0")
        let base1 = version1.split(separator: "-").first.map(String.init) ?? version1
        let base2 = version2.split(separator: "-").first.map(String.init) ?? version2
        let v1Parts = base1.split(separator: ".").compactMap { Int($0) }
        let v2Parts = base2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(v1Parts.count, v2Parts.count)

        for i in 0..<maxLength {
            let v1 = i < v1Parts.count ? v1Parts[i] : 0
            let v2 = i < v2Parts.count ? v2Parts[i] : 0

            if v1 < v2 { return -1 }
            if v1 > v2 { return 1 }
        }

        return 0
    }

    // MARK: - Auth Capabilities

    struct AuthCapabilities {
        let classic: Bool
        let clientTokens: Bool
        let cloudflareBlocked: Bool
        let unreachable: Bool

        var description: String {
            if unreachable { return "Server unreachable" }
            if cloudflareBlocked { return "Server blocked by Cloudflare" }
            var methods: [String] = []
            if classic { methods.append("Classic") }
            if clientTokens { methods.append("Client Tokens") }
            return methods.isEmpty ? "No auth methods available" : methods.joined(separator: ", ")
        }

        var supportsClassic: Bool { classic }
        var supportsClientTokens: Bool { clientTokens }
    }

    /// Minimum server version that supports client API tokens (PR #3114)
    private let minClientTokenVersion = "4.8.0"

    func detectAuthCapabilities(serverURL: String) async -> AuthCapabilities {
        logger.info("Detecting authentication capabilities for: \(serverURL)")

        var classicAuthWorks = false
        var hasClientTokens = false
        var hasCloudflare = false

        do {
            let response = try await apiClient.getHeartbeat(from: serverURL)
            classicAuthWorks = true
            logger.info("Classic auth works - heartbeat successful")

            // Check if classic auth is disabled
            if response.FRONTEND.DISABLE_USERPASS_LOGIN {
                classicAuthWorks = false
                logger.warning("Classic username/password login is disabled on server")
            }

            // Check client token support
            if let clientTokensConfig = response.CLIENT_TOKENS {
                hasClientTokens = clientTokensConfig.ENABLED
                logger.info("Client tokens enabled via heartbeat: \(hasClientTokens)")
            } else {
                // Fallback: check server version >= 4.8.0
                let version = response.SYSTEM.VERSION
                let baseVersion = version.split(separator: "-").first.map(String.init) ?? version
                if compareVersions(baseVersion, minClientTokenVersion) >= 0 {
                    hasClientTokens = true
                    logger.info("Client tokens assumed available (server \(version) >= \(minClientTokenVersion))")
                } else {
                    logger.info("Server \(version) too old for client tokens")
                }
            }
        } catch let error as APIClientError {
            if case .cloudflareProtection = error {
                hasCloudflare = true
                logger.warning("Cloudflare protection detected")
            } else {
                logger.error("Heartbeat failed with error: \(error)")
            }
        } catch {
            logger.error("Heartbeat failed with unexpected error: \(error)")
        }

        if hasCloudflare {
            return AuthCapabilities(classic: false, clientTokens: false, cloudflareBlocked: true, unreachable: false)
        }

        if !classicAuthWorks && !hasClientTokens {
            return AuthCapabilities(classic: false, clientTokens: false, cloudflareBlocked: false, unreachable: true)
        }

        return AuthCapabilities(classic: classicAuthWorks, clientTokens: hasClientTokens, cloudflareBlocked: false, unreachable: false)
    }
}
