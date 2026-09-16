//
//  RommAPIClient+Saves.swift
//  romm
//

import Foundation

// MARK: - Saves API
extension RommAPIClient {

    func uploadSave(
        romId: Int,
        emulator: String?,
        slot: String?,
        deviceId: String?,
        sessionId: String?,
        autocleanup: Bool?,
        overwrite: Bool?,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> SaveSchema {
        // `overwrite` defaults to false server-side, which is a conflict guard,
        // not a replace switch: it refuses the upload when the slot already holds
        // a row this device has no sync history for. Only a caller that has
        // already established it wins sends true (see `SaveSyncRunner`).
        // `autocleanup_limit` is left at the server default (10), nothing here
        // needs a different cap.
        let path = withQuery("api/saves", [
            ("rom_id", String(romId)),
            ("emulator", emulator),
            ("slot", slot),
            ("device_id", deviceId),
            ("session_id", sessionId),
            ("autocleanup", autocleanup.map { $0 ? "true" : "false" }),
            ("overwrite", overwrite.map { $0 ? "true" : "false" })
        ])
        let boundary = "RommSavesBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()
        formData.appendFileField(
            boundary: boundary,
            name: "saveFile",
            fileName: fileName,
            mimeType: "application/octet-stream",
            data: fileData
        )
        if let screenshotData {
            formData.appendFileField(
                boundary: boundary,
                name: "screenshotFile",
                fileName: "screenshot.png",
                mimeType: "image/png",
                data: screenshotData
            )
        }
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await multipartRequest(
            path: path,
            method: .post,
            boundary: boundary,
            formData: formData,
            additionalHeaders: nil
        )
        do {
            return try JSONDecoder().decode(SaveSchema.self, from: data)
        } catch {
            throw APIClientError.decodingError(error)
        }
    }

    func updateSave(
        id: Int,
        emulator: String?,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> SaveSchema {
        let path = withQuery("api/saves/\(id)", [("emulator", emulator)])
        let boundary = "RommSavesBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()
        formData.appendFileField(
            boundary: boundary,
            name: "saveFile",
            fileName: fileName,
            mimeType: "application/octet-stream",
            data: fileData
        )
        if let screenshotData {
            formData.appendFileField(
                boundary: boundary,
                name: "screenshotFile",
                fileName: "screenshot.png",
                mimeType: "image/png",
                data: screenshotData
            )
        }
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await multipartRequest(
            path: path,
            method: .put,
            boundary: boundary,
            formData: formData,
            additionalHeaders: nil
        )
        do {
            return try JSONDecoder().decode(SaveSchema.self, from: data)
        } catch {
            throw APIClientError.decodingError(error)
        }
    }

    func downloadSave(id: Int, deviceId: String?, sessionId: String?) async throws -> Data {
        let path = withQuery("api/saves/\(id)/content", [
            ("device_id", deviceId),
            ("session_id", sessionId)
        ])
        return try await getBinary(path)
    }

    func deleteSaves(ids: [Int]) async throws {
        struct Body: Codable { let saves: [Int] }
        _ = try await post("api/saves/delete", body: Body(saves: ids), responseType: BulkDeleteAck.self)
    }

    /// Tells the server this device has the save's current content, so the next
    /// `negotiate` stops replanning the same download. Without this call the
    /// plan never advances past "download this save" for that device.
    func confirmSaveDownloaded(id: Int, deviceId: String) async throws -> SaveSchema {
        struct Body: Codable { let deviceId: String
            enum CodingKeys: String, CodingKey { case deviceId = "device_id" }
        }
        return try await post("api/saves/\(id)/downloaded", body: Body(deviceId: deviceId), responseType: SaveSchema.self)
    }
}

struct BulkDeleteAck: Codable {
    let msg: String?
}

// MARK: - Multipart File Helper

extension Data {
    mutating func appendFileField(
        boundary: String,
        name: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
