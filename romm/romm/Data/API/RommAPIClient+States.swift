//
//  RommAPIClient+States.swift
//  romm
//

import Foundation

// MARK: - States API
extension RommAPIClient {

    func uploadState(
        romId: Int,
        emulator: String?,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> StateSchema {
        let path = withQuery("api/states", [
            ("rom_id", String(romId)),
            ("emulator", emulator)
        ])
        let boundary = "RommStatesBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()
        formData.appendFileField(
            boundary: boundary,
            name: "stateFile",
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
            return try JSONDecoder().decode(StateSchema.self, from: data)
        } catch {
            throw APIClientError.decodingError(error)
        }
    }

    func updateState(
        id: Int,
        emulator: String?,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> StateSchema {
        let path = withQuery("api/states/\(id)", [("emulator", emulator)])
        let boundary = "RommStatesBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()
        formData.appendFileField(
            boundary: boundary,
            name: "stateFile",
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
            return try JSONDecoder().decode(StateSchema.self, from: data)
        } catch {
            throw APIClientError.decodingError(error)
        }
    }

    func downloadState(id: Int) async throws -> Data {
        return try await getBinary("api/states/\(id)/content")
    }

    func deleteStates(ids: [Int]) async throws {
        struct Body: Codable { let states: [Int] }
        _ = try await post("api/states/delete", body: Body(states: ids), responseType: BulkDeleteAck.self)
    }
}
