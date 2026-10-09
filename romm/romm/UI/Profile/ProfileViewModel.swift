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
    private let deleteLocalGameDataUseCase: PDeleteLocalGameDataUseCase
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
        self.deleteLocalGameDataUseCase = factory.makeDeleteLocalGameDataUseCase()
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
            let useCase = deleteLocalGameDataUseCase
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
        guard summary.hasDownloads else {
            return "No ROMs are downloaded on this device." + unsyncedNote(summary.gamesWithUnsyncedSaves, deletable: false)
        }
        let size = ByteCountFormatter.string(fromByteCount: summary.downloadedBytes, countStyle: .file)
        let roms = summary.downloadedROMCount == 1 ? "1 ROM" : "\(summary.downloadedROMCount) ROMs"
        return "You have \(roms) (\(size)) downloaded on this device. "
            + "Deleting downloads also removes all saves and save states on this device."
            + unsyncedNote(summary.gamesWithUnsyncedSaves, deletable: true)
    }

    private static func unsyncedNote(_ games: Int, deletable: Bool) -> String {
        guard games > 0 else { return "" }
        let subject = games == 1 ? "1 game has" : "\(games) games have"
        let notSynced = "\(subject) saves that are not synced to the server yet."
        return deletable
            ? "\n\nWarning: \(notSynced) Deleting downloads deletes them for good."
            : "\n\n\(notSynced) They stay on this device."
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
