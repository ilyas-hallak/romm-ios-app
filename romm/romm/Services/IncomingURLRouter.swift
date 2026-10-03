//
//  IncomingURLRouter.swift
//  romm
//
//  Single entry point for URLs handed to the app: the `romm://pair` deep link
//  and ROM files opened via "Open In" or a share sheet target. This app uses
//  SwiftUI's scene-based lifecycle, where `UIApplicationDelegate
//  .application(_:open:options:)` is never invoked, so both kinds of URL
//  arrive through `.onOpenURL` on the root view instead.
//

import Foundation

@MainActor
final class IncomingURLRouter {
    static let shared = IncomingURLRouter()

    private let logger = Logger.auth
    private let clientTokenAuthService: ClientTokenAuthService
    private let makeStageIncomingRomUseCase: () -> StageIncomingRomUseCase

    init(
        clientTokenAuthService: ClientTokenAuthService = ClientTokenAuthService(),
        makeStageIncomingRomUseCase: @escaping () -> StageIncomingRomUseCase = {
            DefaultDependencyFactory.shared.makeStageIncomingRomUseCase()
        }
    ) {
        self.clientTokenAuthService = clientTokenAuthService
        self.makeStageIncomingRomUseCase = makeStageIncomingRomUseCase
    }

    func handle(_ url: URL) {
        logger.info("App received URL: \(url.absoluteString)")

        guard url.scheme == "romm" else {
            if url.isFileURL {
                handleIncomingRomFile(url)
            } else {
                logger.warning("Unknown URL scheme: \(url.scheme ?? "none")")
            }
            return
        }

        switch url.host {
        case "pair":
            logger.info("Pairing deep link received")
            if let code = clientTokenAuthService.handleDeepLink(url: url) {
                NotificationCenter.default.post(
                    name: .clientTokenPairingCode,
                    object: nil,
                    userInfo: ["code": code]
                )
            }
        default:
            logger.warning("Unknown URL host: \(url.host ?? "none")")
        }
    }

    /// A ROM handed to the app via "Open In" or a share sheet target. Staged
    /// off the main thread, since the source can be a multi-gigabyte disc
    /// image and the copy would otherwise block the UI; the sheet only shows
    /// up once the copy has actually landed. Security-scoped access is taken
    /// around the copy in `IncomingRomFileRepository.stage(url:)`, since the
    /// source URL (often another app's sandbox) is not guaranteed to stay
    /// readable once this call returns.
    private func handleIncomingRomFile(_ url: URL) {
        Logger.data.info("Received incoming ROM file: \(url.lastPathComponent)")
        let stage = makeStageIncomingRomUseCase()
        Task.detached(priority: .utility) {
            do {
                let staged = try stage.execute(url: url)
                await MainActor.run {
                    IncomingRomFileState.shared.pendingFile = staged
                }
            } catch {
                Logger.data.error("Could not stage incoming ROM file: \(error.localizedDescription)")
            }
        }
    }
}

extension Notification.Name {
    static let clientTokenPairingCode = Notification.Name("clientTokenPairingCode")
}
