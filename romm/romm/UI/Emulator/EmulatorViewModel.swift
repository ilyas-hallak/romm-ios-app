//
//  EmulatorViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 11.12.25.
//

import Foundation
import Observation
import WebKit

@Observable
@MainActor
class EmulatorViewModel {
    // State
    var isLoading: Bool = true
    var showControls: Bool = false
    var errorMessage: String?
    var emulatorURL: URL?

    /// Read once per session, so the frame cannot appear or vanish while a game
    /// is running. A change applies the next time a game is started.
    let showsBezel: Bool

    // Dependencies
    private let rom: Rom
    private let tokenProvider: PTokenProvider
    private let logger = Logger.viewModel

    init(
        rom: Rom,
        tokenProvider: PTokenProvider = TokenProvider(),
        bezelPreference: PEmulatorBezelPreference
    ) {
        self.rom = rom
        self.tokenProvider = tokenProvider
        self.showsBezel = bezelPreference.isEnabled
    }

    func startEmulator() {
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logger.info("🎮 Starting emulator for ROM: \(rom.name) (ID: \(rom.id))")
        logger.info("Platform: \(rom.platformSlug ?? "unknown")")

        guard let serverURLString = tokenProvider.getServerURL() else {
            logger.error("❌ No server configured")
            errorMessage = "No server configured. Please set up your ROMM server in Settings."
            isLoading = false
            return
        }
        logger.info("✅ Server URL: \(serverURLString)")

        // Build ROMM's EmulatorJS player URL
        let cleanServerURL = serverURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanServerURL)/rom/\(rom.id)/ejs") else {
            logger.error("❌ Failed to create emulator URL")
            errorMessage = "Failed to create emulator URL"
            isLoading = false
            return
        }

        emulatorURL = url
        logger.info("✅ Emulator URL: \(url.absoluteString)")
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }


    func cleanup() {
        logger.info("Cleaning up emulator session for ROM: \(rom.name)")
        // Optional: Send "exit" event to server to save state
        // Or rely on server's auto-save
        // Future: Could call /api/states to ensure state is saved
    }

    func clearError() {
        errorMessage = nil
    }

    func clearCacheAndReload() {
        logger.info("🗑️ Clearing cache and reloading emulator...")

        Task {
            // Clear all website data (cookies, cache, local storage, etc.)
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast)
            logger.info("✅ Cache cleared")

            // Reload emulator
            isLoading = true
            errorMessage = nil

            // Re-sync cookies from HTTPCookieStorage
            let sharedCookies = HTTPCookieStorage.shared.cookies ?? []
            logger.info("🍪 Re-syncing \(sharedCookies.count) cookies after cache clear")
            for cookie in sharedCookies {
                await dataStore.httpCookieStore.setCookie(cookie)
            }

            // Trigger reload by resetting and setting URL again
            let currentURL = emulatorURL
            emulatorURL = nil
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            emulatorURL = currentURL

            logger.info("✅ Emulator reloading with fresh cache")
        }
    }
}
