//
//  ServerEndpointUseCases.swift
//  romm
//

import Foundation

protocol PGetServerConnectionUseCase {
    func execute() -> ServerConnection?
}

class GetServerConnectionUseCase: PGetServerConnectionUseCase {
    private let setupRepository: PSetupRepository
    private let endpointRepository: PServerEndpointRepository

    init(setupRepository: PSetupRepository, endpointRepository: PServerEndpointRepository) {
        self.setupRepository = setupRepository
        self.endpointRepository = endpointRepository
    }

    func execute() -> ServerConnection? {
        guard let config = setupRepository.getSetupConfiguration() else { return nil }
        let alternativeURL = config.alternativeServerURL
        return ServerConnection(
            primaryURL: config.serverURL,
            alternativeURL: alternativeURL,
            activeEndpoint: alternativeURL == nil ? .primary : endpointRepository.activeEndpoint
        )
    }
}

protocol PSaveAlternativeServerURLUseCase {
    /// An empty string removes the alternative address.
    func execute(_ input: String) throws
}

class SaveAlternativeServerURLUseCase: PSaveAlternativeServerURLUseCase {
    private let setupRepository: PSetupRepository

    init(setupRepository: PSetupRepository) {
        self.setupRepository = setupRepository
    }

    func execute(_ input: String) throws {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmed.isEmpty else {
            try setupRepository.updateAlternativeServerURL(nil)
            return
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw SetupUseCaseError.invalidURL
        }

        try setupRepository.updateAlternativeServerURL(trimmed)
    }
}

protocol PResolveServerEndpointUseCase {
    @discardableResult
    func execute() async -> ServerEndpoint
}

/// Picks the address the app talks to. The main one wins whenever it answers,
/// the alternative only steps in while it does not.
class ResolveServerEndpointUseCase: PResolveServerEndpointUseCase {
    private let setupRepository: PSetupRepository
    private let endpointRepository: PServerEndpointRepository
    private let logger = Logger.network

    init(setupRepository: PSetupRepository, endpointRepository: PServerEndpointRepository) {
        self.setupRepository = setupRepository
        self.endpointRepository = endpointRepository
    }

    @discardableResult
    func execute() async -> ServerEndpoint {
        guard let config = setupRepository.getSetupConfiguration(),
              let alternativeURL = config.alternativeServerURL else {
            endpointRepository.setActiveEndpoint(.primary)
            return .primary
        }

        let endpoint: ServerEndpoint
        if await endpointRepository.isReachable(config.serverURL) {
            endpoint = .primary
        } else if await endpointRepository.isReachable(alternativeURL) {
            endpoint = .alternative
        } else {
            // Neither answers, most likely offline. Switching would only guess.
            return endpointRepository.activeEndpoint
        }

        if endpoint != endpointRepository.activeEndpoint {
            logger.info("Switching server address to \(endpoint.rawValue)")
        }
        endpointRepository.setActiveEndpoint(endpoint)
        return endpoint
    }
}
