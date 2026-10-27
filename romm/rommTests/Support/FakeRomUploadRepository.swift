//
//  FakeRomUploadRepository.swift
//  rommTests
//
//  Records every call it is asked to make and answers however the test wants.
//

import Foundation
@testable import romm

final class FakeRomUploadRepository: PRomUploadRepository, @unchecked Sendable {
    var availabilityResult: RomUploadAvailability = .available
    var startError: Error?
    var uploadChunkError: Error?
    /// Thrown exactly once, then cleared, so a test can exercise a one-shot
    /// failure (e.g. session expiry) without the retry it provokes failing too.
    var uploadChunkErrorOnce: Error?
    var completeError: Error?
    /// Awaited before every chunk upload "succeeds", so a test can hold a
    /// chunk open (e.g. with `Task.sleep`) to simulate an active upload and
    /// then cancel it mid-flight.
    var chunkGate: (@Sendable () async throws -> Void)?
    /// Awaited before `start(...)` returns, so a test can cancel the job
    /// while the start call is still in flight.
    var startGate: (@Sendable () async throws -> Void)?

    private(set) var startedUploads: [(platformId: Int, fileName: String, fileSize: Int64, totalChunks: Int)] = []
    private(set) var uploadedChunkIndexes: [Int] = []
    private(set) var completedUploadIds: [String] = []
    private(set) var cancelledUploadIds: [String] = []
    /// Every progress closure handed to `uploadChunk`, so a test can invoke
    /// one "late" after the job has already moved on.
    private(set) var capturedProgressHandlers: [(Double) -> Void] = []

    func availability() async -> RomUploadAvailability { availabilityResult }

    func start(platformId: Int, fileName: String, fileSize: Int64, totalChunks: Int) async throws -> String {
        if let startGate { try await startGate() }
        if let startError { throw startError }
        startedUploads.append((platformId, fileName, fileSize, totalChunks))
        return "upload-\(startedUploads.count)"
    }

    func uploadChunk(uploadId: String, index: Int, fileURL: URL, progress: @escaping (Double) -> Void) async throws {
        capturedProgressHandlers.append(progress)
        if let chunkGate {
            try await chunkGate()
        }
        if let uploadChunkErrorOnce {
            self.uploadChunkErrorOnce = nil
            throw uploadChunkErrorOnce
        }
        if let uploadChunkError { throw uploadChunkError }
        uploadedChunkIndexes.append(index)
        progress(1)
    }

    func complete(uploadId: String) async throws {
        if let completeError { throw completeError }
        completedUploadIds.append(uploadId)
    }

    func cancel(uploadId: String) async throws {
        cancelledUploadIds.append(uploadId)
    }
}
