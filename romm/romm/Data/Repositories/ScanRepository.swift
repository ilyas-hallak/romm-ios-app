//
//  ScanRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  A scan can only be started over Socket.IO, there is no REST route for it,
//  and the socket's connect handler resolves the user from the session cookie
//  alone. So this repository signs in for a session, opens the socket and turns
//  the raw events into domain events.
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

        let client = try await connectedClient()
        self.client = client

        let socketEvents = await client.events
        let (stream, continuation) = AsyncStream<LibraryScanEvent>.makeStream(of: LibraryScanEvent.self)

        // Whoever stops reading also closes the socket. A socket left open
        // keeps the server's scan session alive.
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                await self?.teardown()
            }
        }

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

        // An empty platform list means the whole library.
        let metadataSources = await metadataSources()
        let payload: [String: any Sendable] = [
            "platforms": platformIds,
            "type": type.rawValue,
            "roms_ids": [Int](),
            "apis": metadataSources.apis,
            "launchbox_remote_enabled": true,
            "playmatch_enabled": metadataSources.playmatchEnabled
        ]

        do {
            logger.info("Starting a \(type.rawValue) scan over \(platformIds.isEmpty ? "the whole library" : "\(platformIds.count) platforms") with sources \(metadataSources.apis.joined(separator: ", "))")
            try await client.emit("scan", payload)
        } catch {
            continuation.finish()
            await teardown()
            throw error
        }

        return stream
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

    func saveScanCredentials(username: String, password: String) throws {
        try sessionProvider.saveCredentials(username: username, password: password)
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

    // MARK: - Socket

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
