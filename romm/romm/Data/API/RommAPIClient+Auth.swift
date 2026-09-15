//
//  RommAPIClient+Auth.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

// MARK: - Auth API Wrapper
extension RommAPIClient {
    /// Signs in with Basic auth and returns the session cookie the server sets.
    ///
    /// The regular API calls authenticate per request, so nothing needed this
    /// until now. The Socket.IO endpoint is different: it resolves the user from
    /// the session alone and ignores any token on the handshake, so a scan can
    /// only be started with the cookie this call produces.
    func login(username: String, password: String) async throws -> RommSessionCookie {
        let url = try buildURL(path: "api/login")
        let loginString = "\(username):\(password)"
        guard let loginData = loginString.data(using: .utf8) else {
            throw APIClientError.authenticationRequired
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("Basic \(loginData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0
        // The shared session keeps its cookies in the app container, so letting
        // it handle this one would write a credential to disk and attach it to
        // every later request. The caller keeps it in memory instead.
        request.httpShouldHandleCookies = false

        logger.logNetworkRequest(method: HTTPMethod.post.rawValue, url: "api/login")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            logger.logNetworkError(method: HTTPMethod.post.rawValue, url: "api/login", error: error)
            throw APIClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.networkError(URLError(.badServerResponse))
        }
        logger.logNetworkRequest(method: HTTPMethod.post.rawValue, url: "api/login", statusCode: httpResponse.statusCode)

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw APIClientError.authenticationRequired
        default:
            let message = String(data: data, encoding: .utf8) ?? "Login failed"
            throw APIClientError.invalidResponse(httpResponse.statusCode, message)
        }

        guard let cookie = Self.sessionCookie(from: httpResponse, url: url) else {
            logger.error("Login succeeded but no session cookie was set")
            throw APIClientError.authenticationRequired
        }
        Self.forgetStoredSessionCookies(for: url, in: urlSession)
        return cookie
    }

    /// Pulls `romm_session` out of the response. `HTTPCookie` is used rather
    /// than reading the header by hand because several `Set-Cookie` headers
    /// arrive joined into one string.
    private static func sessionCookie(from response: HTTPURLResponse, url: URL) -> RommSessionCookie? {
        guard let headerFields = response.allHeaderFields as? [String: String] else { return nil }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        guard let sessionCookie = cookies.first(where: { $0.name == RommSessionCookie.name }) else { return nil }
        return RommSessionCookie(
            headerValue: "\(sessionCookie.name)=\(sessionCookie.value)",
            expiresAt: sessionCookie.expiresDate
        )
    }

    /// Drops anything the session may still have stored for the server under
    /// the session cookie's name, so the credential really only lives in memory.
    private static func forgetStoredSessionCookies(for url: URL, in session: URLSession) {
        guard let storage = session.configuration.httpCookieStorage else { return }
        storage.cookies(for: url)?
            .filter { $0.name == RommSessionCookie.name }
            .forEach(storage.deleteCookie)
    }

    func logout() async throws -> String {
        let data = try await post("api/logout")
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Users API Wrapper
extension RommAPIClient {
    func getCurrentUser() async throws -> UserSchema {
        return try await get("api/users/me", responseType: UserSchema.self)
    }

    func getUsers() async throws -> [UserSchema] {
        return try await get("api/users", responseType: [UserSchema].self)
    }

    /// Links a RetroAchievements account to the RomM user.
    ///
    /// `PUT api/users/{id}` takes multipart form data and only writes the fields
    /// it receives, so sending `ra_username` alone leaves the rest of the
    /// profile untouched.
    func updateRetroAchievementsUsername(userId: Int, username: String) async throws -> UserSchema {
        let boundary = "RommUserBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()
        formData.appendFormField(boundary: boundary, name: "ra_username", value: username)
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await multipartRequest(
            path: "api/users/\(userId)",
            method: .put,
            boundary: boundary,
            formData: formData,
            additionalHeaders: nil
        )

        do {
            return try JSONDecoder().decode(UserSchema.self, from: data)
        } catch let error as DecodingError {
            throw APIClientError.decodingError(error)
        }
    }
}
