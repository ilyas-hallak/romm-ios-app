//
//  RommAPIClient+Auth.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

// MARK: - Auth API Wrapper
extension RommAPIClient {
    func login() async throws -> String {
        let data = try await post("api/login")
        return String(data: data, encoding: .utf8) ?? ""
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