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
    private let authRepository: PAuthRepository

    init(apiClient: PRommAPIClient, tokenProvider: PTokenProvider, heartbeat: PHeartbeatRepository, authRepository: PAuthRepository) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.heartbeat = heartbeat
        self.authRepository = authRepository
    }

    func availability() async -> RomUploadAvailability {
        // A role without roms.write can never upload, no matter what the
        // current sign-in's token scopes are, so this is checked before them.
        // Skipped (not treated as a failure) when the user can't be fetched, or
        // comes back with no scopes at all, since an older server may simply
        // not send oauth_scopes; the scope and version checks below still apply.
        if let user = try? await authRepository.getCurrentUser(), !user.oauthScopes.isEmpty,
           !user.oauthScopes.contains("roms.write") {
            return .notAllowedForAccount
        }

        guard tokenProvider.hasScope("roms.write") else { return .missingScope }

        if let cached = heartbeat.getLastKnownServerVersion() {
            return availability(for: cached)
        }
        guard let fetched = try? await heartbeat.getHeartbeat().version else { return .unknown }
        return availability(for: fetched)
    }

    private func availability(for version: String) -> RomUploadAvailability {
        ServerVersion.compare(version, minUploadVersion) >= 0
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
}
