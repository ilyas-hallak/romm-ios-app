//
//  ScanRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  Starting a scan goes through `POST /api/tasks/scan` (RomM 5.4.0+), using
//  the app's existing Bearer/client-token auth, no sign-in prompt needed. The
//  live feed of scanned platforms and ROMs is still Socket.IO only though,
//  and that socket's connect handler resolves the user from the session
//  cookie alone, so this repository best-effort opens one for the feed: a
//  scan that was already queued above still runs even if that fails.
//

import Foundation

class ScanRepository: PScanRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient
    private let tokenProvider: PTokenProvider
    private let sessionProvider: PScanSessionProvider

    private var client: SocketIOClient?
    private var forwardTask: Task<Void, Never>?

    init(
        apiClient: PRommAPIClient,
        tokenProvider: PTokenProvider,
        sessionProvider: PScanSessionProvider
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.sessionProvider = sessionProvider
    }

    // MARK: - Start

    func startScan(type: LibraryScanType, platformIds: [Int]) async throws -> AsyncStream<LibraryScanEvent> {
        await teardown()

        // An empty platform list means the whole library.
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
            if let refusal = Self.refusalEvent(for: error) {
                return Self.singleEventStream(refusal)
            }
            throw error
        }

        return await liveFeedStream()
    }

    /// What the socket used to answer with `scan:done_ko` for: a scan already
    /// queued or running, or no worker listening. Any other API error is a
    /// real failure and propagates instead.
    static func refusalEvent(for error: APIClientError) -> LibraryScanEvent? {
        guard case .invalidResponse(let statusCode, let body) = error,
              statusCode == 409 || statusCode == 503 else { return nil }
        let fallback = statusCode == 409 ? "A scan is already in progress." : "No scan worker is available."
        return .failed(detail(from: body) ?? fallback)
    }

    /// FastAPI's error body is `{"detail": "..."}`.
    private static func detail(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data),
              let detail = decoded["detail"], !detail.isEmpty else { return nil }
        return detail
    }

    private static func singleEventStream(_ event: LibraryScanEvent) -> AsyncStream<LibraryScanEvent> {
        AsyncStream { continuation in
            continuation.yield(event)
            continuation.finish()
        }
    }

    // MARK: - Stop

    func stopScan() async throws {
        if let client, await client.isConnected {
            logger.info("Stopping the running scan over the open socket")
            try await client.emit("scan:stop")
            return
        }

        // The scan may have been started elsewhere, in the web UI or in an
        // earlier app session, so stopping opens a socket of its own.
        logger.info("Stopping the running scan over a fresh socket")
        let client = try await connectedClient()
        try await client.emit("scan:stop")
        await client.disconnect()
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
            return ScanMetadataSources(apis: [], playmatchEnabled: false)
        }
    }

    // MARK: - Socket (live feed only, the scan itself is already queued)

    /// Best-effort live feed over the still cookie-only scan socket. The scan
    /// started above is already running server side, so a failure here
    /// (declined sign-in, unreachable socket) ends the stream quietly instead
    /// of throwing; the status poll in the view model picks the run up anyway.
    private func liveFeedStream() async -> AsyncStream<LibraryScanEvent> {
        let (stream, continuation) = AsyncStream<LibraryScanEvent>.makeStream(of: LibraryScanEvent.self)

        // Whoever stops reading also closes the socket. A socket left open
        // keeps the server's scan session alive.
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                await self?.teardown()
            }
        }

        do {
            let client = try await connectedClient()
            self.client = client
            let socketEvents = await client.events

            forwardTask = Task { [weak self] in
                for await socketEvent in socketEvents {
                    guard let scanEvent = ScanEventMapper.map(socketEvent) else { continue }
                    continuation.yield(scanEvent)

                    if case .finished = scanEvent { break }
                    if case .failed = scanEvent { break }
                }
                continuation.finish()
                await self?.teardown()
            }
        } catch {
            logger.warning("Could not open the live scan feed, the scan keeps running on the server: \(error)")
            continuation.finish()
        }

        return stream
    }

    private func connectedClient() async throws -> SocketIOClient {
        let cookie = try await sessionProvider.sessionCookie()
        let url = try socketURL()
        let client = SocketIOClient(
            serverURL: url,
            cookie: cookie,
            sessionDelegate: PrivateNetworkURLSessionDelegate()
        )

        do {
            try await client.connect()
        } catch {
            await client.disconnect()
            // A refused handshake usually means the session is no longer good,
            // so the next attempt signs in again instead of reusing it.
            if case SocketIOError.connectRejected = error {
                sessionProvider.invalidate()
            }
            throw error
        }
        return client
    }

    private func teardown() async {
        forwardTask?.cancel()
        forwardTask = nil
        let client = self.client
        self.client = nil
        await client?.disconnect()
    }

    /// `wss://<host>/ws/socket.io/?EIO=4&transport=websocket`, keeping the port
    /// and any base path the server is mounted under.
    private func socketURL() throws -> URL {
        guard let serverURL = tokenProvider.getServerURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverURL.isEmpty else {
            throw ScanAuthError.serverNotConfigured
        }

        let trimmed = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed), components.host != nil else {
            throw ScanAuthError.serverNotConfigured
        }

        let isSecure = components.scheme?.lowercased() == "https" || components.scheme?.lowercased() == "wss"
        components.scheme = isSecure ? "wss" : "ws"

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/ws/socket.io/" : "/\(basePath)/ws/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]

        guard let url = components.url else {
            throw ScanAuthError.serverNotConfigured
        }
        return url
    }
}
