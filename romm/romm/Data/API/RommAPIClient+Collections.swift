//
//  RommAPIClient+Collections.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

// MARK: - Collections API Wrapper
extension RommAPIClient {
    func getCollections(limit: Int? = nil, offset: Int? = nil) async throws -> [CollectionSchema] {
        return try await get("api/collections", responseType: [CollectionSchema].self)
    }

    func getCollection(id: Int) async throws -> CollectionSchema {
        return try await get("api/collections/\(id)", responseType: CollectionSchema.self)
    }

    func getVirtualCollections(type: String, limit: Int? = nil) async throws -> [VirtualCollectionSchema] {
        let path = withQuery("api/collections/virtual", [
            ("type", type),
            ("limit", limit.map(String.init))
        ])
        return try await get(path, responseType: [VirtualCollectionSchema].self)
    }

    func getVirtualCollection(id: String) async throws -> VirtualCollectionSchema {
        return try await get("api/collections/virtual/\(id)", responseType: VirtualCollectionSchema.self)
    }

    /// Creates a collection. `is_public` and `is_favorite` are query parameters on this
    /// endpoint rather than multipart fields. `is_favorite` can only be set here, because
    /// PUT /api/collections/{id} does not accept it.
    func createCollection(
        name: String,
        description: String,
        isPublic: Bool,
        isFavorite: Bool = false,
        artwork: URL? = nil
    ) async throws -> CollectionSchema {
        logger.info("🚀 Creating collection - name: '\(name)', isPublic: \(isPublic), isFavorite: \(isFavorite)")
        return try await createOrUpdateCollection(
            method: .post,
            path: "api/collections?is_public=\(isPublic)&is_favorite=\(isFavorite)",
            name: name,
            description: description,
            romIds: nil,
            artwork: artwork
        )
    }

    func updateCollection(
        id: Int,
        name: String,
        description: String,
        isPublic: Bool,
        romIds: [Int]? = nil,
        artwork: URL? = nil
    ) async throws -> CollectionSchema {
        logger.info("🔄 Updating collection \(id) - name: '\(name)', romIds: \(romIds?.count ?? 0)")
        return try await createOrUpdateCollection(
            method: .put,
            path: "api/collections/\(id)?is_public=\(isPublic)&remove_cover=false",
            name: name,
            description: description,
            romIds: romIds,
            artwork: artwork
        )
    }

    func deleteCollection(id: Int) async throws -> String {
        let data = try await delete("api/collections/\(id)")
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Adds ROMs to a collection without touching the ones already in it. Preferred over
    /// updateCollection, which replaces the whole ROM list and therefore loses concurrent
    /// changes made from another client.
    func addRomsToCollection(id: Int, romIds: [Int]) async throws -> CollectionSchema {
        logger.info("➕ Adding \(romIds.count) ROM(s) to collection \(id)")
        return try await makeRequest(
            path: "api/collections/\(id)/roms",
            method: .post,
            body: try JSONEncoder().encode(CollectionRomsPayload(romIds: romIds)),
            responseType: CollectionSchema.self
        )
    }

    func removeRomsFromCollection(id: Int, romIds: [Int]) async throws -> CollectionSchema {
        logger.info("➖ Removing \(romIds.count) ROM(s) from collection \(id)")
        return try await makeRequest(
            path: "api/collections/\(id)/roms",
            method: .delete,
            body: try JSONEncoder().encode(CollectionRomsPayload(romIds: romIds)),
            responseType: CollectionSchema.self
        )
    }

    // MARK: - Private Helper

    private func createOrUpdateCollection(
        method: HTTPMethod,
        path: String,
        name: String,
        description: String,
        romIds: [Int]? = nil,
        artwork: URL? = nil
    ) async throws -> CollectionSchema {
        guard let serverURL = tokenProvider.getServerURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverURL.isEmpty else {
            logger.error("Missing server configuration")
            throw APIClientError.noConfiguration
        }

        let cleanServerURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let boundary = "RommCollectionBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()

        formData.appendFormField(boundary: boundary, name: "name", value: name)

        if !description.isEmpty {
            formData.appendFormField(boundary: boundary, name: "description", value: description)
        } else {
            formData.appendFormField(boundary: boundary, name: "description", value: "")
        }

        formData.appendFormField(boundary: boundary, name: "url_cover", value: "")

        if let romIds, !romIds.isEmpty {
            let romIdsJson = "[\(romIds.map(String.init).joined(separator: ","))]"
            formData.appendFormField(boundary: boundary, name: "rom_ids", value: romIdsJson)
        } else {
            formData.appendFormField(boundary: boundary, name: "rom_ids", value: "undefined")
        }

        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        logger.debug("📝 \(method.rawValue) request path: \(path)")
        logger.debug("📝 ROM IDs: \(romIds?.description ?? "nil")")

        let additionalHeaders: [String: String] = [
            "Origin": cleanServerURL,
            "Referer": "\(cleanServerURL)/",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin"
        ]

        do {
            let data = try await multipartRequest(
                path: path,
                method: method,
                boundary: boundary,
                formData: formData,
                additionalHeaders: additionalHeaders
            )
            let decoded = try JSONDecoder().decode(CollectionSchema.self, from: data)
            logger.info("✅ Collection \(method.rawValue.lowercased()) successful: id=\(decoded.id), name='\(decoded.name)'")
            return decoded
        } catch let error as DecodingError {
            throw APIClientError.decodingError(error)
        } catch let error as APIClientError {
            throw error
        } catch {
            throw APIClientError.networkError(error)
        }
    }
}

// MARK: - Request Payloads

private struct CollectionRomsPayload: Encodable {
    let romIds: [Int]

    enum CodingKeys: String, CodingKey {
        case romIds = "rom_ids"
    }
}

// MARK: - Multipart Helper

private extension Data {
    mutating func appendFormField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}