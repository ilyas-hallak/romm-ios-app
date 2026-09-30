//
//  ServerEndpointRepository.swift
//  romm
//

import Foundation

protocol PServerEndpointRepository {
    var activeEndpoint: ServerEndpoint { get }
    func setActiveEndpoint(_ endpoint: ServerEndpoint)
    func isReachable(_ serverURL: String) async -> Bool
}

/// Remembers which address of the server answered last, and checks whether an
/// address answers at all.
final class ServerEndpointRepository: PServerEndpointRepository {
    private static let activeEndpointKey = "server.activeEndpoint"

    /// Short on purpose: the check runs before the first request after launch,
    /// and a local address seen from outside does not fail, it just never answers.
    private static let probeTimeout: TimeInterval = 4

    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral.withoutCookies()
        configuration.timeoutIntervalForRequest = probeTimeout
        configuration.timeoutIntervalForResource = probeTimeout
        configuration.waitsForConnectivity = false
        // Same rules as the API client, so a self-signed server on the local
        // network or behind Tailscale counts as reachable.
        return URLSession(configuration: configuration, delegate: PrivateNetworkURLSessionDelegate(), delegateQueue: nil)
    }()

    private let userDefaults: UserDefaults
    private let session: URLSession
    private let logger = Logger.network

    init(userDefaults: UserDefaults = .standard, session: URLSession = ServerEndpointRepository.probeSession) {
        self.userDefaults = userDefaults
        self.session = session
    }

    var activeEndpoint: ServerEndpoint {
        userDefaults.string(forKey: Self.activeEndpointKey).flatMap(ServerEndpoint.init) ?? .primary
    }

    func setActiveEndpoint(_ endpoint: ServerEndpoint) {
        userDefaults.set(endpoint.rawValue, forKey: Self.activeEndpointKey)
    }

    func isReachable(_ serverURL: String) async -> Bool {
        let base = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/heartbeat") else { return false }

        do {
            let (_, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(statusCode)
        } catch {
            logger.info("Server not reachable at \(base): \(error.localizedDescription)")
            return false
        }
    }
}
