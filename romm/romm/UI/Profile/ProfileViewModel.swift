//
//  ProfileViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 08.08.25.
//

import Foundation
import os
import Observation

@Observable
@MainActor
class ProfileViewModel {
    private let logger = Logger.viewModel
    private let getLocalDataSummaryUseCase: PGetLocalDataSummaryUseCase
    private let deleteAllDownloadedROMsUseCase: PDeleteAllDownloadedROMsUseCase
    private let clearSetupConfigurationUseCase: PClearSetupConfigurationUseCase
    private let getGroupRomsUseCase: PGetGroupRomsUseCase
    private let saveGroupRomsUseCase: PSaveGroupRomsUseCase
    private let getServerConnectionUseCase: PGetServerConnectionUseCase

    private(set) var serverConnection: ServerConnection?

    /// Shown in the logout confirmation, nil when it could not be read.
    private(set) var logoutSummary: LocalDataSummary?
    var isLogoutConfirmationPresented = false

    var groupRomsByMetaId: Bool {
        didSet {
            guard oldValue != groupRomsByMetaId else { return }
            saveGroupRomsUseCase.execute(groupRomsByMetaId)
        }
    }

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getLocalDataSummaryUseCase = factory.makeGetLocalDataSummaryUseCase()
        self.deleteAllDownloadedROMsUseCase = factory.makeDeleteAllDownloadedROMsUseCase()
        self.clearSetupConfigurationUseCase = factory.makeClearSetupConfigurationUseCase()
        self.getGroupRomsUseCase = factory.makeGetGroupRomsUseCase()
        self.saveGroupRomsUseCase = factory.makeSaveGroupRomsUseCase()
        self.getServerConnectionUseCase = factory.makeGetServerConnectionUseCase()
        self.groupRomsByMetaId = getGroupRomsUseCase.execute()
    }

    func refreshServerConnection() {
        serverConnection = getServerConnectionUseCase.execute()
    }
    
    /// Reads what is stored locally, then asks how to log out.
    func prepareLogout() async {
        let useCase = getLocalDataSummaryUseCase
        do {
            logoutSummary = try await Task.detached(priority: .userInitiated) { try useCase.execute() }.value
        } catch {
            logger.error("Reading local data for logout failed: \(error)")
            logoutSummary = nil
        }
        isLogoutConfirmationPresented = true
    }

    /// There is no server session to end: every request carries its own
    /// credentials, so logging out means forgetting them on this device.
    func logout(deletingDownloads: Bool) async {
        logger.info("Logging out (deleting downloads: \(deletingDownloads))...")
        if deletingDownloads {
            let useCase = deleteAllDownloadedROMsUseCase
            do {
                try await Task.detached(priority: .userInitiated) { try useCase.execute() }.value
            } catch {
                logger.error("Deleting downloads on logout failed: \(error)")
            }
        }
        restartSetup()
    }

    var logoutMessage: String { Self.logoutMessage(for: logoutSummary) }

    static func logoutMessage(for summary: LocalDataSummary?) -> String {
        guard let summary else {
            return "You will be signed out and returned to the setup screen."
        }
        var message: String
        if summary.hasDownloads {
            let size = ByteCountFormatter.string(fromByteCount: summary.downloadedBytes, countStyle: .file)
            let roms = summary.downloadedROMCount == 1 ? "1 ROM" : "\(summary.downloadedROMCount) ROMs"
            message = "You have \(roms) (\(size)) downloaded on this device."
        } else {
            message = "No ROMs are downloaded on this device."
        }
        switch summary.gamesWithUnsyncedSaves {
        case 0:
            break
        case 1:
            message += "\n\n1 game has saves that are not synced to the server yet. They stay on this device."
        case let count:
            message += "\n\n\(count) games have saves that are not synced to the server yet. They stay on this device."
        }
        return message
    }

    func restartSetup() {
        logger.info("Restarting setup...")

        do {
            try clearSetupConfigurationUseCase.execute()
            logger.info("Setup restart complete")

            // Notify AppViewModel to transition to setup state
            NotificationCenter.default.post(name: .restartSetupRequested, object: nil)
        } catch {
            logger.error("Failed to restart setup: \(error)")
        }
    }
}

// MARK: - Notification Names
extension NSNotification.Name {
    static let restartSetupRequested = NSNotification.Name("RestartSetupRequested")
    static let sessionExpired = NSNotification.Name("SessionExpired")
}
