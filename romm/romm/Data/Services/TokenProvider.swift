//
//  TokenProvider.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import Foundation

// MARK: - Token Provider Protocol
protocol PTokenProvider {
    func getAuthToken() -> String?
    func getServerURL() -> String?
    func getUsername() -> String?
    func getPassword() -> String?
    func isConfigured() -> Bool
    
    func getAuthMethod() -> AuthMethod

    // Client Token Methods
    func getClientToken() -> String?
    func getClientTokenInfo() -> ClientTokenInfo?
    func hasScope(_ scope: String) -> Bool
    var availableScopes: [String]? { get }
}

// MARK: - Token Provider Implementation
class TokenProvider: PTokenProvider {
    
    private let setupRepository: PSetupRepository
    private let configurationService: ConfigurationService
    private let logger = Logger.auth
    
    init(setupRepository: PSetupRepository = SetupRepository(),
         configurationService: ConfigurationService = DefaultConfigurationService.shared) {
        self.setupRepository = setupRepository
        self.configurationService = configurationService
    }
    
    func getAuthToken() -> String? {
        logger.debug("Getting auth token...")
        
        // Try to get token from setup repository first (preferred)
        if let setupConfig = setupRepository.getSetupConfiguration() {
            logger.info("Setup config found - Server: \(setupConfig.serverURL)")
            logger.debug("Setup config found - Username: \(setupConfig.username)")
            logger.debug("Setup config found - Setup Date: \(setupConfig.setupDate)")
            logger.debug("Setup config has refresh token: \(setupConfig.refreshToken != nil)")
            
            if let token = setupConfig.token, !token.isEmpty {
                logger.info("Token found in setup repository (length: \(token.count))")
                return token
            } else {
                logger.warning("Setup config exists but token is nil/empty")
            }
        } else {
            logger.debug("No setup configuration found")
        }
        
        // Fallback to configuration service
        if let config = configurationService.getConfiguration() {
            logger.info("Fallback config found - Server: \(config.serverURL)")
            
            if let token = config.token, !token.isEmpty {
                logger.info("Token found in configuration service (length: \(token.count))")
                return token
            } else {
                logger.warning("Fallback config exists but token is nil/empty")
            }
        } else {
            logger.debug("No fallback configuration found")
        }
        
        logger.error("No auth token found anywhere")
        return nil
    }
    
    func getServerURL() -> String? {
        logger.debug("Getting server URL...")
        
        // Try to get from setup repository first (preferred)
        if let setupConfig = setupRepository.getSetupConfiguration() {
            logger.info("Server URL found in setup repository: \(setupConfig.serverURL)")
            return setupConfig.serverURL
        }
        
        // Fallback to configuration service
        if let config = configurationService.getConfiguration() {
            logger.info("Server URL found in configuration service: \(config.serverURL)")
            return config.serverURL
        }
        
        logger.warning("No server URL found")
        return nil
    }
    
    func getUsername() -> String? {
        logger.debug("Getting username...")
        
        // Try to get from setup repository first (preferred)
        if let setupConfig = setupRepository.getSetupConfiguration() {
            logger.info("Username found in setup repository: \(setupConfig.username)")
            return setupConfig.username
        }
        
        // Fallback to configuration service
        if let config = configurationService.getConfiguration() {
            let username = config.username
            logger.info("Username found in configuration service: \(username)")
            return username
        }
        
        logger.warning("No username found")
        return nil
    }
    
    func getPassword() -> String? {
        logger.debug("Getting password...")
        
        // Try to get from setup repository first (preferred)
        if let setupConfig = setupRepository.getSetupConfiguration() {
            if let password = setupConfig.password {
                logger.info("Password found in setup repository")
                return password
            }
        }
        
        // Fallback to configuration service
        if let config = configurationService.getConfiguration() {
            if let password = config.password {
                logger.info("Password found in configuration service")
                return password
            }
        }
        
        logger.warning("No password found")
        return nil
    }
    
    func isConfigured() -> Bool {
        let authMethod = getAuthMethod()

        if authMethod == .clientToken {
            let hasToken = getClientToken() != nil
            let hasServerURL = getServerURL() != nil
            let configured = hasToken && hasServerURL
            logger.info("Client token configuration check - Token: \(hasToken), Server: \(hasServerURL), Configured: \(configured)")
            return configured
        }

        let hasUsername = getUsername() != nil
        let hasPassword = getPassword() != nil
        let hasServerURL = getServerURL() != nil
        let configured = hasUsername && hasPassword && hasServerURL
        logger.info("Configuration check - Username: \(hasUsername), Password: \(hasPassword), Server: \(hasServerURL), Configured: \(configured)")
        return configured
    }
    
    func getAuthMethod() -> AuthMethod {
        let method = setupRepository.getAuthMethod()
        logger.debug("Current auth method: \(method.displayName)")
        return method
    }

    // MARK: - Client Token Methods

    func getClientToken() -> String? {
        logger.debug("Getting client token...")
        let service = ClientTokenAuthService()
        guard let token = service.getToken() else {
            logger.debug("No client token found")
            return nil
        }
        logger.info("Client token found")
        return token
    }

    func getClientTokenInfo() -> ClientTokenInfo? {
        let service = ClientTokenAuthService()
        return service.getTokenInfo()
    }

    func hasScope(_ scope: String) -> Bool {
        guard let scopes = availableScopes else { return true }
        return scopes.contains(scope)
    }

    var availableScopes: [String]? {
        guard getAuthMethod() == .clientToken else { return nil }
        return getClientTokenInfo()?.scopes
    }
}

// MARK: - Mock Token Provider for Testing
class MockTokenProvider: PTokenProvider {
    var mockToken: String?
    var mockServerURL: String?
    var mockUsername: String?
    var mockPassword: String?
    var mockConfigured: Bool = false
    var mockAuthMethod: AuthMethod = .classic
    var mockClientToken: String?
    var mockClientTokenInfo: ClientTokenInfo?
    
    init(token: String? = nil, serverURL: String? = nil, username: String? = nil, password: String? = nil, configured: Bool = false) {
        self.mockToken = token
        self.mockServerURL = serverURL
        self.mockUsername = username
        self.mockPassword = password
        self.mockConfigured = configured
    }
    
    func getAuthToken() -> String? {
        return mockToken
    }
    
    func getServerURL() -> String? {
        return mockServerURL
    }
    
    func getUsername() -> String? {
        return mockUsername
    }
    
    func getPassword() -> String? {
        return mockPassword
    }
    
    func isConfigured() -> Bool {
        return mockConfigured
    }
    
    func getAuthMethod() -> AuthMethod {
        return mockAuthMethod
    }

    func getClientToken() -> String? { return mockClientToken }
    func getClientTokenInfo() -> ClientTokenInfo? { return mockClientTokenInfo }
    func hasScope(_ scope: String) -> Bool {
        guard let scopes = availableScopes else { return true }
        return scopes.contains(scope)
    }
    var availableScopes: [String]? { return mockClientTokenInfo?.scopes }
}
