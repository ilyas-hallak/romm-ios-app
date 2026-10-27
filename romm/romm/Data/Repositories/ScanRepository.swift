//
//  ScanRepository.swift
//  romm
//
//  Starting a scan goes through `POST /api/tasks/scan` (RomM 5.4.0+, #5014
//  upstream), using the app's existing Bearer/client-token auth, no sign-in
//  prompt needed. Following the run is `PTasksRepository`'s job, polling
//  `GET /api/tasks/status`.
//

import Foundation

class ScanRepository: PScanRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient

    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }

    func startScan(type: LibraryScanType, platformIds: [Int]) async throws {
        let metadataSources = await metadataSources()
        let request = ScanStartRequest(
            type: type.rawValue,
            platforms: platformIds,
            platformFsSlugs: [],
            romsIds: [],
            apis: metadataSources.apis,
            launchboxRemoteEnabled: true
        )

        logger.info("Starting a \(type.rawValue) scan over \(platformIds.isEmpty ? "the whole library" : "\(platformIds.count) platforms") with sources \(metadataSources.apis.joined(separator: ", "))")

        do {
            try await apiClient.startLibraryScan(request)
        } catch let error as APIClientError {
            if let message = Self.refusalMessage(for: error) {
                throw ScanStartError.refused(message)
            }
            throw LibraryScanAccessError.mapIfMissingScope(error)
        }
    }

    /// What the socket used to answer with `scan:done_ko` for: a scan already
    /// queued or running, or no worker listening. Any other API error is a
    /// real failure and propagates instead.
    static func refusalMessage(for error: APIClientError) -> String? {
        guard case .invalidResponse(let statusCode, let body) = error,
              statusCode == 409 || statusCode == 503 else { return nil }
        let fallback = statusCode == 409 ? "A scan is already in progress." : "No scan worker is available."
        return detail(from: body) ?? fallback
    }

    /// FastAPI's error body is `{"detail": "..."}`.
    private static func detail(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data),
              let detail = decoded["detail"], !detail.isEmpty else { return nil }
        return detail
    }

    /// Every metadata source the server has configured, which is the web UI's
    /// default too. The app deliberately has no source picker, the scan sheet
    /// only asks for a scan type and platforms.
    ///
    /// A heartbeat that does not answer does not block the scan: a quick scan
    /// still reconciles the files, it just finds no metadata for them.
    private func metadataSources() async -> ScanMetadataSources {
        do {
            let heartbeat = try await apiClient.getHeartbeat()
            return ScanMetadataSourcesMapper.mapFromAPI(heartbeat.METADATA_SOURCES)
        } catch {
            logger.warning("Could not read the metadata sources, scanning without them: \(error)")
            return ScanMetadataSources(apis: [])
        }
    }
}
