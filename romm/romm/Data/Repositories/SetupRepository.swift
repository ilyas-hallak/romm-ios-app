//
//  SetupRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import Foundation

// MARK: - Setup Data Models
struct SetupConfiguration: Codable {
    let serverURL: String
    let username: String
    let password: String?
    let token: String?
    let refreshToken: String?
    let setupDate: Date
    let version: String
    let allowIncompatibleVersionLogin: Bool

    enum CodingKeys: String, CodingKey {
        case serverURL
        case username
        case password
        case token
        case refreshToken
        case setupDate
        case version
        case allowIncompatibleVersionLogin
    }

    init(
        serverURL: String,
        username: String,
        password: String?,
        token: String?,
        refreshToken: String?,
        setupDate: Date,
        version: String,
        allowIncompatibleVersionLogin: Bool = false
    ) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.token = token
        self.refreshToken = refreshToken
        self.setupDate = setupDate
        self.version = version
        self.allowIncompatibleVersionLogin = allowIncompatibleVersionLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(String.self, forKey: .serverURL)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        setupDate = try container.decode(Date.self, forKey: .setupDate)
        version = try container.decode(String.self, forKey: .version)
        allowIncompatibleVersionLogin = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowIncompatibleVersionLogin
        ) ?? false
    }
}

// MARK: - Setup Repository Protocol
protocol PSetupRepository {
    func saveSetupConfiguration(_ config: SetupConfiguration) throws
    func getSetupConfiguration() -> SetupConfiguration?
    func isSetupComplete() -> Bool
    func clearSetupConfiguration() throws
    func updateToken(_ token: String) throws
    func saveAndValidateConfiguration(
        serverURL: String,
        username: String,
        password: String,
        allowIncompatibleVersionLogin: Bool
    ) async throws -> SetupConfiguration
    
    func getAuthMethod() -> AuthMethod
    func saveAuthMethod(_ method: AuthMethod) throws

    // Client Token Methods
    func saveClientTokenSetup(serverURL: String, tokenName: String, version: String, allowIncompatibleVersionLogin: Bool) throws
    func clearClientTokenData() throws
}

// MARK: - Setup Repository Implementation
class SetupRepository: PSetupRepository {
    
    // MARK: - Properties
    private let logger = Logger.data
    
    // MARK: - Constants
    private let userDefaultsPrefix = "setup_"
    
    // UserDefaults Keys
    private let setupConfigurationKey = "setup_configuration_json"
    
    // MARK: - Public Methods
    
    func saveSetupConfiguration(_ config: SetupConfiguration) throws {
        logger.info("Saving setup configuration as JSON...")
        logger.debug("Server URL: \(config.serverURL)")
        logger.debug("Username: \(config.username)")
        logger.debug("Setup Date: \(config.setupDate)")
        logger.debug("Version: \(config.version)")
        logger.debug("Has Password: \(config.password != nil)")
        logger.debug("Has Token: \(config.token != nil)")
        logger.debug("Has Refresh Token: \(config.refreshToken != nil)")
        logger.debug("Allow Incompatible Version Login: \(config.allowIncompatibleVersionLogin)")
        
        do {
            let jsonData = try JSONEncoder().encode(config)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            UserDefaults.standard.set(jsonString, forKey: setupConfigurationKey)
            
            logger.debug("JSON data size: \(jsonData.count) bytes")
            logger.info("Setup configuration saved as JSON successfully")
            
        } catch {
            logger.error("Failed to encode configuration as JSON: \(error)")
            throw SetupRepositoryError.invalidData
        }
    }
    
    func getSetupConfiguration() -> SetupConfiguration? {
        logger.debug("Reading setup configuration from JSON...")
        
        guard let jsonString = UserDefaults.standard.string(forKey: setupConfigurationKey),
              !jsonString.isEmpty else {
            logger.warning("No setup configuration JSON found")
            return nil
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.error("Failed to convert JSON string to data")
            return nil
        }
        
        do {
            let config = try JSONDecoder().decode(SetupConfiguration.self, from: jsonData)
            
            logger.info("Setup configuration loaded from JSON")
            logger.debug("Server URL: \(config.serverURL)")
            logger.debug("Username: \(config.username)")
            logger.debug("Has Password: \(config.password != nil)")
            logger.debug("Has Access Token: \(config.token != nil)")
            logger.debug("Has Refresh Token: \(config.refreshToken != nil)")
            logger.debug("Allow Incompatible Version Login: \(config.allowIncompatibleVersionLogin)")
            logger.debug("Setup Date: \(config.setupDate)")
            logger.debug("Version: \(config.version)")
            
            return config
            
        } catch {
            logger.error("Failed to decode configuration from JSON: \(error)")
            return nil
        }
    }
    
    func isSetupComplete() -> Bool {
        let config = getSetupConfiguration()
        let isComplete = config != nil
        logger.debug("Setup complete check: \(isComplete)")
        return isComplete
    }
    
    func clearSetupConfiguration() throws {
        logger.info("Clearing setup configuration...")
        if getAuthMethod() == .clientToken {
            try clearClientTokenData()
        }
        logger.info("Setup configuration cleared")
    }
    
    func updateToken(_ token: String) throws {
        logger.info("Updating token...")
        
        // Load current configuration
        guard let config = getSetupConfiguration() else {
            logger.error("No existing configuration to update")
            throw SetupRepositoryError.dataNotFound
        }
        
        // Create new configuration with updated token
        let updatedConfig = SetupConfiguration(
            serverURL: config.serverURL,
            username: config.username,
            password: config.password,
            token: token,
            refreshToken: config.refreshToken,
            setupDate: config.setupDate,
            version: config.version,
            allowIncompatibleVersionLogin: config.allowIncompatibleVersionLogin
        )
        
        // Save updated configuration
        try saveSetupConfiguration(updatedConfig)
        logger.info("Token updated in JSON configuration")
    }
    
    @MainActor
    func saveAndValidateConfiguration(
        serverURL: String,
        username: String,
        password: String,
        allowIncompatibleVersionLogin: Bool
    ) async throws -> SetupConfiguration {
        let connectionLogger = ConnectionLogger.shared
        connectionLogger.startNewConnection()

        logger.info("Starting configuration validation and save...")
        logger.debug("Server URL: \(serverURL)")
        logger.debug("Username: \(username)")
        logger.debug("Allow Incompatible Version Login: \(allowIncompatibleVersionLogin)")

        // Clean URL
        let cleanURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionLogger.logURLValidation(cleanURL)

        // Validate URL format
        guard URL(string: cleanURL) != nil else {
            connectionLogger.logURLValidationError("Invalid URL format")
            connectionLogger.finishConnection(success: false)
            throw SetupRepositoryError.invalidData
        }
        connectionLogger.logURLValidationSuccess()

        do {
            // Test API connection with Basic Auth and get token
            let token = try await validateBasicAuthConnection(serverURL: cleanURL, username: username, password: password)

            // Create configuration with current timestamp and version
            let setupConfig = SetupConfiguration(
                serverURL: cleanURL,
                username: username,
                password: password,
                token: token,
                refreshToken: nil,
                setupDate: Date(),
                version: getCurrentAppVersion(),
                allowIncompatibleVersionLogin: allowIncompatibleVersionLogin
            )

            // Save to storage
            try saveSetupConfiguration(setupConfig)

            logger.info("Configuration validated and saved successfully")
            connectionLogger.finishConnection(success: true)
            return setupConfig
        } catch {
            connectionLogger.finishConnection(success: false)
            throw error
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func validateBasicAuthConnection(serverURL: String, username: String, password: String) async throws -> String {
        let connectionLogger = await ConnectionLogger.shared
        logger.info("Validating Basic Auth connection and getting token...")

        // First, try to get a token via OAuth2
        guard let tokenURL = URL(string: "\(serverURL)/api/token") else {
            logger.error("Invalid token URL: \(serverURL)/api/token")
            await connectionLogger.log("Invalid token endpoint URL", type: .error)
            throw SetupRepositoryError.invalidData
        }

        // Detect and log IP type
        if let host = tokenURL.host {
            await connectionLogger.logHostResolution(host)
            let ipType = detectIPType(host: host)
            await connectionLogger.logIPTypeDetected(ipType)
        }

        logger.debug("Getting token from: \(tokenURL.absoluteString)")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        // OAuth2 form parameters
        let formParameters = [
            "grant_type=password",
            "username=\(username.addingURLFormValueEncoding())",
            "password=\(password.addingURLFormValueEncoding())",
            "scope="
        ]
        let formData = formParameters.joined(separator: "&")
        guard let httpBody = formData.data(using: .utf8) else {
            logger.error("Failed to encode form data")
            await connectionLogger.log("Failed to encode request", type: .error)
            throw SetupRepositoryError.invalidData
        }
        request.httpBody = httpBody

        logger.debug("Request headers: \(request.allHTTPHeaderFields ?? [:])")
        logger.debug("Request body: \(formData)")

        await connectionLogger.logConnecting()
        await connectionLogger.log("POST \(tokenURL.path)", type: .info)

        do {
            logger.debug("Sending token request...")
            await connectionLogger.logTLSHandshake()

            // Use URLSession with private network delegate for self-signed certs
            let sessionDelegate = PrivateNetworkURLSessionDelegate()
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0
            configuration.waitsForConnectivity = true
            let session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)

            let (data, response) = try await session.data(for: request)

            logger.debug("Response received")
            logger.debug("Response data size: \(data.count) bytes")
            logger.debug("Response data: \(String(data: data, encoding: .utf8) ?? "nil")")

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Not an HTTP response")
                await connectionLogger.log("Invalid response from server", type: .error)
                throw SetupRepositoryError.dataNotFound
            }

            logger.debug("HTTP Status Code: \(httpResponse.statusCode)")
            await connectionLogger.log("Response status: \(httpResponse.statusCode)", type: .info)

            switch httpResponse.statusCode {
            case 200...299:
                // Parse token response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let accessToken = json["access_token"] as? String else {
                    logger.error("No access token in response")
                    await connectionLogger.log("Invalid response format", type: .error, details: "No access_token in response")
                    throw SetupRepositoryError.invalidData
                }

                logger.info("Token received successfully")
                logger.debug("Token length: \(accessToken.count)")
                await connectionLogger.logAuthSuccess()
                return accessToken

            case 401:
                logger.error("Authentication failed - invalid credentials")
                await connectionLogger.logAuthFailed("Invalid username or password")
                throw SetupRepositoryError.invalidData

            case 403:
                logger.error("Authentication failed - forbidden")
                await connectionLogger.logAuthFailed("Access forbidden")
                throw SetupRepositoryError.invalidData

            case 404:
                logger.error("API endpoint not found")
                await connectionLogger.log("API endpoint not found", type: .error, details: "Is this a RomM server?")
                throw SetupRepositoryError.dataNotFound

            default:
                logger.error("Token request failed with status: \(httpResponse.statusCode)")
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                await connectionLogger.log("Server error (\(httpResponse.statusCode))", type: .error, details: errorBody)
                throw SetupRepositoryError.dataNotFound
            }

        } catch let error as URLError {
            logger.error("URLError: \(error.localizedDescription)")
            await connectionLogger.logNetworkError(error)
            throw SetupRepositoryError.dataNotFound
        } catch let error as SetupRepositoryError {
            throw error
        } catch {
            logger.error("Unexpected error: \(error)")
            await connectionLogger.logNetworkError(error)
            throw SetupRepositoryError.dataNotFound
        }
    }

    private func detectIPType(host: String) -> String {
        // Check for localhost
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return "Localhost"
        }

        // Check for Tailscale (100.64.0.0/10 - CGNAT range)
        if host.hasPrefix("100.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), second >= 64 && second <= 127 {
                return "Tailscale VPN"
            }
        }

        // Check for private Class A (10.0.0.0/8)
        if host.hasPrefix("10.") {
            return "Private Network (Class A)"
        }

        // Check for private Class B (172.16.0.0/12)
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), second >= 16 && second <= 31 {
                return "Private Network (Class B)"
            }
        }

        // Check for private Class C (192.168.0.0/16)
        if host.hasPrefix("192.168.") {
            return "Private Network (Class C)"
        }

        // Check for IPv6 link-local (fe80::/10)
        if host.lowercased().hasPrefix("fe80:") {
            return "IPv6 Link-Local"
        }

        // Otherwise, assume public
        return "Public Server"
    }
    
    private func getCurrentAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var authMethodKey: String { "\(userDefaultsPrefix)auth_method" }

    func getAuthMethod() -> AuthMethod {
        logger.debug("📖 Reading auth method...")
        
        guard let methodString = UserDefaults.standard.string(forKey: authMethodKey),
              let method = AuthMethod(rawValue: methodString) else {
            logger.debug("No auth method found, defaulting to classic")
            return .classic
        }
        
        logger.info("✅ Auth method: \(method.displayName)")
        return method
    }
    
    func saveAuthMethod(_ method: AuthMethod) throws {
        logger.info("💾 Saving auth method: \(method.displayName)")
        
        UserDefaults.standard.set(method.rawValue, forKey: authMethodKey)
        
        logger.info("✅ Auth method saved")
    }
    
    // MARK: - Client Token Methods

    func saveClientTokenSetup(serverURL: String, tokenName: String, version: String, allowIncompatibleVersionLogin: Bool) throws {
        logger.info("Saving client token setup configuration...")
        let setupConfig = SetupConfiguration(
            serverURL: serverURL,
            username: tokenName.isEmpty ? "Token User" : tokenName,
            password: nil,
            token: nil,
            refreshToken: nil,
            setupDate: Date(),
            version: version,
            allowIncompatibleVersionLogin: allowIncompatibleVersionLogin
        )
        try saveSetupConfiguration(setupConfig)
        try saveAuthMethod(.clientToken)
        logger.info("Client token setup saved")
    }

    func clearClientTokenData() throws {
        logger.info("Clearing client token data...")
        let service = ClientTokenAuthService()
        service.clearToken()
        logger.info("Client token data cleared")
    }

    // MARK: - Private Helper Methods (continued)
}

// MARK: - Setup Repository Error
enum SetupRepositoryError: LocalizedError {
    case keychainError(OSStatus)
    case dataNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .dataNotFound:
            return "Setup data not found"
        case .invalidData:
            return "Invalid setup data"
        }
    }
}
