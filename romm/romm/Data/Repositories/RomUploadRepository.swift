//
//  RomUploadRepository.swift
//  romm
//

import Foundation

final class RomUploadRepository: PRomUploadRepository {
    /// The chunked upload API is only served from RomM 4.8.0 onwards.
    private let minUploadVersion = "4.8.0"

    private let apiClient: PRommAPIClient
    private let tokenProvider: PTokenProvider
    private let heartbeat: PHeartbeatRepository

    init(apiClient: PRommAPIClient, tokenProvider: PTokenProvider, heartbeat: PHeartbeatRepository) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.heartbeat = heartbeat
    }

    func availability() async -> RomUploadAvailability {
        guard tokenProvider.hasScope("roms.write") else { return .missingScope }

        if let cached = heartbeat.getLastKnownServerVersion() {
            return availability(for: cached)
        }
        guard let fetched = try? await heartbeat.getHeartbeat().version else { return .unknown }
        return availability(for: fetched)
    }

    private func availability(for version: String) -> RomUploadAvailability {
        Self.compareVersions(version, minUploadVersion) >= 0
            ? .available
            : .serverTooOld(version: version)
    }

    func start(platformId: Int, fileName: String, fileSize: Int64, totalChunks: Int) async throws -> String {
        try await apiClient.startRomUpload(
            platformId: platformId,
            fileName: fileName,
            fileSize: fileSize,
            totalChunks: totalChunks
        )
    }

    func uploadChunk(uploadId: String, index: Int, fileURL: URL, progress: @escaping (Double) -> Void) async throws {
        try await apiClient.uploadRomChunk(uploadId: uploadId, index: index, fileURL: fileURL, progressHandler: progress)
    }

    func complete(uploadId: String) async throws {
        try await apiClient.completeRomUpload(uploadId: uploadId)
    }

    func cancel(uploadId: String) async throws {
        try await apiClient.cancelRomUpload(uploadId: uploadId)
    }

    // MARK: - Version compare

    /// Minimal semantic-version compare, kept here so this repository stays
    /// self-contained (same approach as `SyncDeviceRepository`).
    private static func compareVersions(_ a: String, _ b: String) -> Int {
        if a == "development" { return 1 }
        if b == "development" { return -1 }
        let baseA = a.split(separator: "-").first.map(String.init) ?? a
        let baseB = b.split(separator: "-").first.map(String.init) ?? b
        let pa = baseA.split(separator: ".").compactMap { Int($0) }
        let pb = baseB.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return -1 }
            if x > y { return 1 }
        }
        return 0
    }
}
