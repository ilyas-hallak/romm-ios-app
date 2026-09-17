//
//  ConfigurationService.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import Foundation
import Security

protocol ConfigurationService {
    func saveConfiguration(serverURL: String, username: String, password: String) async throws
    func getConfiguration() -> AppConfiguration?
    func isConfigured() -> Bool
    func clearConfiguration() throws
    func refreshToken() async throws -> Bool
}

struct AppConfiguration {
    let serverURL: String
    let username: String
    let password: String?
    let token: String?
    let refreshToken: String?
}

enum ConfigurationError: LocalizedError {
    case keychainError(OSStatus)
    case invalidCredentials
    case networkError
    case encodingError
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .invalidCredentials:
            return "Invalid credentials - check username and password"
        case .networkError:
            return "Network connection error - check server URL and internet connection"
        case .encodingError:
            return "Data encoding error"
        case .invalidURL:
            return "Invalid server URL - make sure it starts with http:// or https://"
        }
    }
}

class DefaultConfigurationService: ConfigurationService {
    static let shared = DefaultConfigurationService()
    
    private let keychainService = "com.romm.app"
    private let setupConfigurationKey = "setup_configuration_json"
    private let logger = Logger.data
    
    private init() {}
    
    func saveConfiguration(serverURL: String, username: String, password: String) async throws {
        logger.info("Save configuration called - this is now handled by SetupRepository")
        logger.debug("Input URL: '\(serverURL)'")
        logger.debug("Input Username: '\(username)'")
        
        // This method is deprecated - configuration is now saved via SetupRepository.saveAndValidateConfiguration
        // Just validate the connection for backward compatibility
        let cleanURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        try await testBasicAuthConnection(serverURL: cleanURL, username: username, password: password)
        
        logger.warning("Configuration validation successful, but data should be saved via SetupRepository")
    }
    
    func getConfiguration() -> AppConfiguration? {
        logger.debug("Getting configuration from JSON...")
        
        guard let jsonString = UserDefaults.standard.string(forKey: setupConfigurationKey),
              !jsonString.isEmpty else {
            logger.debug("No configuration JSON found")
            return nil
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.error("Failed to convert JSON string to data")
            return nil
        }
        
        do {
            // Parse JSON manually instead of using SetupConfiguration struct
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let serverURL = json["serverURL"] as? String,
                  let username = json["username"] as? String else {
                logger.error("Invalid JSON structure")
                return nil
            }
            
            let password = json["password"] as? String
            let token = json["token"] as? String
            let refreshToken = json["refreshToken"] as? String
            
            // Convert to AppConfiguration
            let appConfig = AppConfiguration(
                serverURL: serverURL,
                username: username,
                password: password,
                token: token,
                refreshToken: refreshToken
            )
            
            logger.info("Configuration loaded from JSON - Server: \(serverURL), Username: \(username)")
            logger.debug("Password: \(password != nil ? "found" : "not found")")
            logger.debug("Access Token: \(token != nil ? "found (length: \(token!.count))" : "not found")")
            logger.debug("Refresh Token: \(refreshToken != nil ? "found (length: \(refreshToken!.count))" : "not found")")
            
            return appConfig
            
        } catch {
            logger.error("Failed to decode configuration from JSON: \(error)")
            return nil
        }
    }
    
    func isConfigured() -> Bool {
        return getConfiguration() != nil
    }
    
    func clearConfiguration() throws {
        logger.info("Clearing configuration...")
        UserDefaults.standard.removeObject(forKey: setupConfigurationKey)
        logger.info("Configuration cleared")
    }
    
    func refreshToken() async throws -> Bool {
        logger.info("Starting token refresh...")
        
        guard let config = getConfiguration(),
              let refreshToken = config.refreshToken else {
            logger.warning("No refresh token available")
            return false
        }
        
        guard let url = URL(string: "\(config.serverURL)/api/token") else {
            logger.error("Invalid server URL for token refresh")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        // Use refresh token to get new access token
        let formParameters = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken.addingURLFormValueEncoding())"
        ]
        let formData = formParameters.joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)
        
        logger.debug("Sending refresh token request...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type during refresh")
                return false
            }
            
            logger.debug("Refresh response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let newAccessToken = json["access_token"] as? String else {
                    logger.error("Failed to parse refresh response")
                    return false
                }
                
                let newRefreshToken = json["refresh_token"] as? String
                
                // Update tokens in JSON configuration
                if let jsonString = UserDefaults.standard.string(forKey: setupConfigurationKey),
                   let jsonData = jsonString.data(using: .utf8),
                   var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    // Update tokens in existing JSON
                    json["token"] = newAccessToken
                    if let newRefreshToken = newRefreshToken {
                        json["refreshToken"] = newRefreshToken
                    }
                    json["setupDate"] = ISO8601DateFormatter().string(from: Date())
                    
                    // Save updated JSON
                    if let updatedJsonData = try? JSONSerialization.data(withJSONObject: json),
                       let updatedJsonString = String(data: updatedJsonData, encoding: .utf8) {
                        UserDefaults.standard.set(updatedJsonString, forKey: setupConfigurationKey)
                    }
                }
                
                logger.info("Token refreshed successfully")
                logger.debug("New access token length: \(newAccessToken.count)")
                return true
                
            } else {
                logger.error("Token refresh failed with status: \(httpResponse.statusCode)")
                logger.debug("Response: \(String(data: data, encoding: .utf8) ?? "nil")")
                return false
            }
            
        } catch {
            logger.error("Token refresh error: \(error)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func testBasicAuthConnection(serverURL: String, username: String, password: String) async throws {
        logger.info("Testing Basic Auth connection...")
        logger.debug("Server URL: \(serverURL)")
        logger.debug("Username: \(username)")

        guard let url = URL(string: "\(serverURL)/api/users/me") else {
            logger.error("Invalid URL: \(serverURL)/api/users/me")
            throw ConfigurationError.invalidURL
        }

        logger.debug("Full URL: \(url.absoluteString)")

        // Create Basic Auth header
        let loginString = "\(username):\(password)"
        guard let loginData = loginString.data(using: .utf8) else {
            logger.error("Failed to encode credentials")
            throw ConfigurationError.encodingError
        }
        let base64LoginString = loginData.base64EncodedString()
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0
        
        logger.debug("Request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        do {
            logger.debug("Sending Basic Auth test request...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            logger.debug("Response received")
            logger.debug("Response data size: \(data.count) bytes")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Not an HTTP response")
                throw ConfigurationError.networkError
            }
            
            logger.debug("HTTP Status Code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                logger.error("Basic Auth test failed with status: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 401 {
                    throw ConfigurationError.invalidCredentials
                } else {
                    throw ConfigurationError.networkError
                }
            }
            
            logger.info("Basic Auth connection test successful")
            
        } catch let error as URLError {
            logger.error("URLError: \(error.localizedDescription)")
            logger.debug("Error code: \(error.code.rawValue)")
            if let failingURL = error.failingURL {
                logger.debug("Failing URL: \(failingURL)")
            }
            throw ConfigurationError.networkError
        } catch let error as ConfigurationError {
            throw error
        } catch {
            logger.error("Unexpected error: \(error)")
            logger.debug("Error type: \(type(of: error))")
            throw ConfigurationError.networkError
        }
    }
    
    private func saveToKeychain(key: String, value: String) throws {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConfigurationError.keychainError(status)
        }
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func removeFromKeychain(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConfigurationError.keychainError(status)
        }
    }
}
