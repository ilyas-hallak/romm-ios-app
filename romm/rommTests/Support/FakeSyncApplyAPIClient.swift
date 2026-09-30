//
//  FakeSyncApplyAPIClient.swift
//  rommTests
//
//  Shared test double for the save/sync surface of PRommAPIClient, used by
//  ApplySyncUseCaseTests.
//

import Foundation
@testable import romm

/// Records every save/sync call `ApplySyncUseCase` can make and answers with
/// canned data, so a plan's effect on the wire can be checked without a
/// server. Everything else still traps via `StubRommAPIClient`.
final class FakeSyncApplyAPIClient: StubRommAPIClient, @unchecked Sendable {

    struct UploadCall: Equatable {
        let romId: Int
        let emulator: String?
        let slot: String?
        let deviceId: String?
        let sessionId: Int?
        let overwrite: Bool
        let fileName: String
        let fileData: Data
    }

    struct UpdateCall: Equatable {
        let id: Int
        let emulator: String?
        let deviceId: String?
        let fileName: String
        let fileData: Data
    }

    struct DownloadCall: Equatable {
        let id: Int
        let deviceId: String?
        let sessionId: Int?
        let optimistic: Bool
    }

    struct ConfirmCall: Equatable {
        let id: Int
        let deviceId: String
    }

    struct CompleteCall: Equatable {
        let id: Int
        let operationsCompleted: Int
        let operationsFailed: Int
    }

    private(set) var uploadCalls: [UploadCall] = []
    private(set) var updateCalls: [UpdateCall] = []
    private(set) var downloadCalls: [DownloadCall] = []
    private(set) var confirmCalls: [ConfirmCall] = []
    private(set) var completeCalls: [CompleteCall] = []

    /// What `downloadSave` answers with, keyed by the save id asked for.
    var downloadDataBySaveId: [Int: Data] = [:]
    /// Makes the matching call throw instead of answering normally.
    var uploadErrorsByRomId: [Int: Error] = [:]
    var downloadErrorsBySaveId: [Int: Error] = [:]
    var completeSessionError: Error?

    override func uploadSave(
        romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: Int?,
        overwrite: Bool, fileName: String, fileData: Data, screenshotData: Data?
    ) async throws -> SaveSchema {
        uploadCalls.append(UploadCall(
            romId: romId, emulator: emulator, slot: slot, deviceId: deviceId, sessionId: sessionId,
            overwrite: overwrite, fileName: fileName, fileData: fileData
        ))
        if let error = uploadErrorsByRomId[romId] { throw error }
        return Self.makeSave(id: uploadCalls.count, romId: romId, fileName: fileName)
    }

    override func updateSave(
        id: Int, emulator: String?, deviceId: String?, fileName: String, fileData: Data, screenshotData: Data?
    ) async throws -> SaveSchema {
        updateCalls.append(UpdateCall(
            id: id, emulator: emulator, deviceId: deviceId, fileName: fileName, fileData: fileData
        ))
        return Self.makeSave(id: id, romId: 0, fileName: fileName)
    }

    override func downloadSave(
        id: Int, deviceId: String?, sessionId: Int?, optimistic: Bool
    ) async throws -> Data {
        downloadCalls.append(DownloadCall(id: id, deviceId: deviceId, sessionId: sessionId, optimistic: optimistic))
        if let error = downloadErrorsBySaveId[id] { throw error }
        return downloadDataBySaveId[id] ?? Data()
    }

    override func confirmSaveDownloaded(id: Int, deviceId: String) async throws {
        confirmCalls.append(ConfirmCall(id: id, deviceId: deviceId))
    }

    override func completeSyncSession(
        id: Int, operationsCompleted: Int, operationsFailed: Int
    ) async throws -> SyncSessionSchema {
        completeCalls.append(CompleteCall(id: id, operationsCompleted: operationsCompleted, operationsFailed: operationsFailed))
        if let completeSessionError { throw completeSessionError }
        return SyncSessionSchema(
            id: id, status: "completed", operationsPlanned: nil,
            operationsCompleted: operationsCompleted, operationsFailed: operationsFailed, errorMessage: nil
        )
    }

    private static func makeSave(id: Int, romId: Int, fileName: String) -> SaveSchema {
        SaveSchema(
            id: id, romId: romId, userId: 1, fileName: fileName, fileNameNoTags: fileName,
            fileNameNoExt: fileName, fileExtension: "", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
            emulator: nil, screenshot: nil
        )
    }
}

struct FakeSyncApplyAPIError: Error, LocalizedError {
    var errorDescription: String? { "fake sync apply failure" }
}
