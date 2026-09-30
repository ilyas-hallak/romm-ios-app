//
//  RommAPIClient+Saves.swift
//  romm
//

import Foundation

// MARK: - Saves API
extension RommAPIClient {

    /// `POST /api/saves` — uploads a save the server does not have.
    ///
    /// - Parameters:
    ///   - sessionId: The negotiation this upload belongs to, so the server can
    ///     count it against the session. Nil outside a sync.
    ///   - overwrite: Replaces a same-named file instead of filing a second
    ///     copy beside it.
    func uploadSave(
        romId: Int,
        emulator: String?,
        slot: String?,
        deviceId: String?,
        sessionId: Int?,
        overwrite: Bool,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> SaveSchema {
        let path = withQuery("api/saves", [
            ("rom_id", String(romId)),
            ("emulator", emulator),
            ("slot", slot),
            ("device_id", deviceId),
            ("session_id", sessionId.map(String.init)),
            // Only sent when set, so the server keeps its own default.
            ("overwrite", overwrite ? "true" : nil)
        ])
        return try await uploadSaveFile(
            path: path,
            method: .post,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    /// `PUT /api/saves/{id}` — replaces the contents of a save already on the
    /// server, which is how a conflict resolved in favour of this device is
    /// applied.
    func updateSave(
        id: Int,
        emulator: String?,
        deviceId: String?,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> SaveSchema {
        let path = withQuery("api/saves/\(id)", [
            ("emulator", emulator),
            ("device_id", deviceId)
        ])
        return try await uploadSaveFile(
            path: path,
            method: .put,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    /// `GET /api/saves/{id}/content` — the save's bytes.
    ///
    /// - Parameter optimistic: The server's default marks the save as synced to
    ///   this device the moment it hands the bytes over. Pass `false` to have
    ///   that wait for `confirmSaveDownloaded`, which is what a sync wants:
    ///   writing the file here can still fail.
    func downloadSave(
        id: Int,
        deviceId: String?,
        sessionId: Int?,
        optimistic: Bool
    ) async throws -> Data {
        let path = withQuery("api/saves/\(id)/content", [
            ("device_id", deviceId),
            ("session_id", sessionId.map(String.init)),
            ("optimistic", optimistic ? nil : "false")
        ])
        return try await getBinary(path)
    }

    /// `POST /api/saves/{id}/downloaded` — confirms the bytes arrived and were
    /// written, which is what records the save as synced to this device.
    func confirmSaveDownloaded(id: Int, deviceId: String) async throws {
        _ = try await post(
            "api/saves/\(id)/downloaded",
            body: SaveDeviceRequest(deviceId: deviceId),
            responseType: SaveSchema.self
        )
    }

    func deleteSaves(ids: [Int]) async throws {
        struct Body: Codable { let saves: [Int] }
        _ = try await post("api/saves/delete", body: Body(saves: ids), responseType: BulkDeleteAck.self)
    }

    // MARK: - Private

    /// The multipart body both upload and update send, which differ only in
    /// path and method.
    private func uploadSaveFile(
        path: String,
        method: HTTPMethod,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> SaveSchema {
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
            method: method,
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
