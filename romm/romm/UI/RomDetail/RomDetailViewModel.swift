//
//  RomDetailViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation
import Observation

/// Wrapper so the "Open In…" share sheet can be presented via `.sheet(item:)`.
struct ShareURLsItem: Identifiable {
    let id = UUID()
    let urls: [URL]
    let tempDirectory: URL?
}

@Observable
@MainActor
class RomDetailViewModel {
    var romDetails: RomDetails?
    var isLoading: Bool = false
    var errorMessage: String?
    var actualFavoriteStatus: Bool = false // True favorite status from Collections API
    var manual: Manual?
    var manualPDFData: Data?
    var isLoadingManual: Bool = false
    var romCollectionsCount: Int = 0
    var selectedSiblingId: Int? = nil // Currently selected sibling (nil = current ROM)
    var originalRomDetails: RomDetails? = nil // Store original ROM with all siblings
    var siblingDetails: [Int: String] = [:] // Cache sibling names (id -> display name)
    var saves: [SaveSchema] = []
    var states: [StateSchema] = []
    var isLoadingSaves: Bool = false
    var isLoadingStates: Bool = false

    // Emulator
    var showingEmulator: Bool = false
    var canPlayEmulator: Bool = false
    var showingEmulatorFeatureHint: Bool = false
    var launchDecision: LaunchDecision? = nil
    var isLaunchingEmulator: Bool = false

    // Local download (playing happens in the Downloads tab)
    var isDownloaded: Bool = false
    var downloadError: String? = nil
    var shareItem: ShareURLsItem? = nil
    var showAddedToast: Bool = false

    // External emulator handoff
    /// File waiting to be handed to an external emulator through the "Open in" menu.
    var openInItem: OpenInItem? = nil
    /// Play destination, mirrored into state so the button reacts to a settings change.
    var playTarget: PlayTarget = .builtIn

    /// Shared, app-wide download queue. Downloads keep running after this screen
    /// is dismissed; the queue is viewable from the Downloads tab.
    let downloadQueue = DownloadQueueManager.shared

    /// Combined button state from on-disk status and the live queue.
    enum DownloadButtonState: Equatable {
        case idle
        case queued
        case downloading(Double?) // 0...1, or nil when size is unknown
        case downloaded
        case failed
    }

    func downloadButtonState(forRomId id: Int) -> DownloadButtonState {
        if isDownloaded { return .downloaded }
        switch downloadQueue.status(forRomId: id) {
        case .queued: return .queued
        case .downloading(let progress): return .downloading(progress)
        case .finished: return .downloaded
        case .failed: return .failed
        case nil: return .idle
        }
    }

    private let logger = Logger.viewModel

    private let apiClient: PRommAPIClient
    private let getRomDetailsUseCase: GetRomDetailsUseCase
    private let toggleRomFavoriteUseCase: ToggleRomFavoriteUseCase
    private let checkRomFavoriteStatusUseCase: CheckRomFavoriteStatusUseCase
    private let loadManualUseCase: LoadManualUseCase
    private let getCollectionsUseCase: GetCollectionsUseCase
    private let platformEngineSupport: PPlatformEngineSupport
    private let launchEmulatorUseCase: PLaunchEmulatorUseCase
    private let updateLastPlayedUseCase: PUpdateLastPlayedUseCase
    private let getDownloadedROMUseCase: PGetDownloadedROMUseCase
    private let getROMShareFilesUseCase: PGetROMShareFilesUseCase
    private let playTargetPreference: PPlayTargetPreference
    private let externalEmulatorHandoffStore: PExternalEmulatorHandoffStore
    private let externalAppLauncher: PExternalAppLauncher

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared,
         apiClient: PRommAPIClient = RommAPIClient.shared) {
        self.apiClient = apiClient
        self.getRomDetailsUseCase = factory.makeGetRomDetailsUseCase()
        self.toggleRomFavoriteUseCase = factory.makeToggleRomFavoriteUseCase()
        self.checkRomFavoriteStatusUseCase = factory.makeCheckRomFavoriteStatusUseCase()
        self.loadManualUseCase = factory.makeLoadManualUseCase()
        self.getCollectionsUseCase = factory.makeGetCollectionsUseCase()
        self.platformEngineSupport = factory.makePlatformEngineSupport()
        self.launchEmulatorUseCase = factory.makeLaunchEmulatorUseCase()
        self.updateLastPlayedUseCase = factory.makeUpdateLastPlayedUseCase()
        self.getDownloadedROMUseCase = factory.makeGetDownloadedROMUseCase()
        self.getROMShareFilesUseCase = factory.makeGetROMShareFilesUseCase()
        self.playTargetPreference = factory.playTargetPreference
        self.externalEmulatorHandoffStore = factory.externalEmulatorHandoffStore
        self.externalAppLauncher = factory.externalAppLauncher
        self.playTarget = factory.playTargetPreference.current
    }
    
    func loadRomDetails(romId: Int) async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Load ROM details, favorite status, and collections in parallel
            async let detailsTask = getRomDetailsUseCase.execute(romId: romId)
            async let favoriteStatusTask = checkRomFavoriteStatusUseCase.execute(romId: romId)
            async let collectionsTask = getCollectionsUseCase.execute()
            
            let (details, favoriteStatus, collections) = try await (detailsTask, favoriteStatusTask, collectionsTask)
            
            romDetails = details
            actualFavoriteStatus = favoriteStatus
            
            // Store original ROM details with siblings if this is the first load
            if originalRomDetails == nil {
                originalRomDetails = details
                // Pre-load sibling details for better UX
                await loadSiblingDetails()
            }
            
            // Count how many collections contain this ROM
            romCollectionsCount = collections.filter { $0.romIds.contains(romId) }.count

            // Check emulator support
            checkEmulatorSupport()

            isLoading = false

            logger.info("Loaded ROM details for \(details.name) - Favorite: \(favoriteStatus), Collections: \(romCollectionsCount), Emulator: \(canPlayEmulator)")
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            logger.error("Error loading ROM details: \(error)")
        }
    }
    
    func toggleFavorite(originalRom: Rom) {
        logger.debug("Toggling favorite for ROM \(originalRom.id): \(originalRom.name)")

        Task { @MainActor in
            do {
                // Use the actual favorite status from Collections API
                let currentFavoriteState = actualFavoriteStatus
                let romId = romDetails?.id ?? originalRom.id

                let newFavoriteState = !currentFavoriteState
                logger.debug("Current favorite state: \(currentFavoriteState) -> New state: \(newFavoriteState)")

                try await toggleRomFavoriteUseCase.execute(
                    romId: romId,
                    isFavorite: newFavoriteState
                )

                logger.info("Successfully toggled favorite state")

                // Update the actual favorite status
                actualFavoriteStatus = newFavoriteState

                // Also update the romDetails if available
                if let romDetails = romDetails {
                    self.romDetails = RomDetails(
                        id: romDetails.id,
                        name: romDetails.name,
                        fileName: romDetails.fileName,
                        summary: romDetails.summary,
                        urlCover: romDetails.urlCover,
                        platformId: romDetails.platformId,
                        isFavourite: newFavoriteState,
                        hasRetroAchievements: romDetails.hasRetroAchievements,
                        genre: romDetails.genre,
                        developer: romDetails.developer,
                        publisher: romDetails.publisher,
                        releaseDate: romDetails.releaseDate,
                        pathManual: romDetails.pathManual,
                        sizeBytes: romDetails.sizeBytes,
                        sha1Hash: romDetails.sha1Hash,
                        md5Hash: romDetails.md5Hash,
                        crcHash: romDetails.crcHash,
                        platformDisplayName: romDetails.platformDisplayName
                    )
                }

            } catch {
                logger.error("Error toggling favorite: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func loadManual(for romId: Int) async {
        guard !isLoadingManual else { return }
        
        isLoadingManual = true
        
        do {
            manual = try await loadManualUseCase.execute(for: romId)
            
            if manual != nil {
                // Load PDF data
                let pdfData = try await loadManualUseCase.getManualPDFData(for: romId)
                
                // Validate PDF data
                if let data = pdfData, !data.isEmpty {
                    // Check if data starts with PDF magic bytes
                    let pdfHeader = data.prefix(4)
                    if pdfHeader.starts(with: Data([0x25, 0x50, 0x44, 0x46])) { // "%PDF"
                        manualPDFData = data
                        logger.info("PDF data validated - Size: \(data.count) bytes")
                    } else {
                        logger.warning("Invalid PDF data - Header: \(pdfHeader.map { String(format: "%02x", $0) }.joined())")
                        manualPDFData = nil
                    }
                } else {
                    logger.warning("Empty or nil PDF data")
                    manualPDFData = nil
                }
            }
            
            isLoadingManual = false
            logger.info("Loaded manual for ROM \(romId) - Available: \(manual != nil)")
        } catch {
            isLoadingManual = false
            logger.error("Error loading manual: \(error)")
            manualPDFData = nil
            // Don't set error message for manual loading, just log it
        }
    }
    
    func loadSaves(for romId: Int) async {
        guard !isLoadingSaves else { return }
        
        isLoadingSaves = true
        
        do {
            saves = try await apiClient.getSaves(romId: romId)
            isLoadingSaves = false
            logger.info("Loaded \(saves.count) saves for ROM \(romId)")
        } catch {
            isLoadingSaves = false
            logger.error("Error loading saves: \(error)")
            saves = []
        }
    }
    
    func loadStates(for romId: Int) async {
        guard !isLoadingStates else { return }
        
        isLoadingStates = true
        
        do {
            states = try await apiClient.getStates(romId: romId)
            isLoadingStates = false
            logger.info("Loaded \(states.count) states for ROM \(romId)")
        } catch {
            isLoadingStates = false
            logger.error("Error loading states: \(error)")
            states = []
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    func switchToSibling(_ siblingId: Int?) async {
        guard let siblingId = siblingId else {
            // Switch back to original ROM
            if let originalDetails = originalRomDetails {
                romDetails = originalDetails
                selectedSiblingId = nil
            }
            return
        }
        
        // Load details for the selected sibling
        await loadRomDetails(romId: siblingId)
        
        // After loading, set the selected sibling ID to track which one we switched to
        selectedSiblingId = siblingId
    }
    
    var availableRomOptions: [(id: Int, name: String)] {
        // Use original ROM details to always show the complete sibling list
        guard let originalDetails = originalRomDetails else { return [] }
        
        var options: [(id: Int, name: String)] = []
        
        // Add original ROM as first option - use fsName (with extension) if available
        let originalRomDisplayName = originalDetails.fsName ?? originalDetails.fsNameNoExt ?? originalDetails.name
        options.append((originalDetails.id, originalRomDisplayName))
        
        // Add siblings - use cached details or fallback to basic info
        for sibling in originalDetails.siblings {
            let displayName = siblingDetails[sibling.id] ?? sibling.displayNameWithExtension
            options.append((sibling.id, displayName))
        }
        
        return options
    }
    
    var currentRomName: String {
        guard let romDetails = romDetails else { return "-" }
        
        // Use fsName (with extension) for distinction, fallback to fsNameNoExt, then name
        return romDetails.fsName ?? romDetails.fsNameNoExt ?? romDetails.name
    }
    
    private func loadSiblingDetails() async {
        guard let originalDetails = originalRomDetails else { return }

        // Load details for each sibling to get their specific names
        for sibling in originalDetails.siblings {
            if siblingDetails[sibling.id] == nil {
                do {
                    let details = try await getRomDetailsUseCase.execute(romId: sibling.id)
                    let displayName = details.fsName ?? details.fsNameNoExt ?? details.name
                    siblingDetails[sibling.id] = displayName
                } catch {
                    // Fallback to sibling's own display name if API call fails
                    siblingDetails[sibling.id] = sibling.displayNameWithExtension
                }
            }
        }
    }

    // MARK: - Emulator

    func checkEmulatorSupport() {
        guard let platformSlug = romDetails?.platformDisplayName else {
            canPlayEmulator = false
            return
        }

        canPlayEmulator = platformEngineSupport.isEmulationAvailable(for: platformSlug)
        logger.debug("Emulator support for '\(platformSlug)': \(canPlayEmulator)")
    }

    func launchEmulator(rom: Rom) async {
        guard let decision = await resolveLaunch(rom: rom) else { return }
        present(decision, rom: rom)
    }

    /// Picks the engine without presenting anything, so callers can tell whether
    /// offering a resume makes sense at all.
    func resolveLaunch(rom: Rom) async -> LaunchDecision? {
        logger.debug("Play tapped for ROM \(rom.id)")
        guard ExperimentalFeatureSettings.shared.isEmulatorEnabled else {
            logger.info("Experimental emulator disabled, showing hint")
            showingEmulatorFeatureHint = true
            return nil
        }

        isLaunchingEmulator = true
        let result = await launchEmulatorUseCase.execute(rom: rom)

        switch result {
        case .success(let decision):
            return decision
        case .failure(let error):
            logger.error("Failed to launch emulator: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isLaunchingEmulator = false
            return nil
        }
    }

    func present(_ decision: LaunchDecision, rom: Rom) {
        logger.info("Launching emulator for ROM: \(rom.name) — decision: \(String(describing: decision))")
        self.launchDecision = decision
        markPlayed(romId: rom.id)
    }

    /// Reports the ROM as played to the server, best effort.
    private func markPlayed(romId: Int) {
        Task { [updateLastPlayedUseCase, logger] in
            do {
                try await updateLastPlayedUseCase.execute(romId: romId)
            } catch {
                logger.warning("Failed to update last_played for ROM \(romId): \(error)")
            }
        }
    }

    func emulatorPresentationDidEnd() {
        isLaunchingEmulator = false
    }

    // MARK: - Local Download

    /// Refreshes whether this ROM is already downloaded to the device.
    func refreshDownloadState(romId: Int) {
        isDownloaded = (try? getDownloadedROMUseCase.execute(romId: romId)) != nil
    }

    /// Adds the ROM to the shared download queue and shows a brief confirmation.
    /// The actual transfer runs in `DownloadQueueManager`, so the user can leave
    /// this screen and watch progress from the Downloads tab.
    func downloadROM(rom: Rom) {
        guard !isDownloaded else { return }
        downloadQueue.enqueue(rom: rom)
        showAddedToast = true
    }

    /// Prepares the downloaded ROM files for the iOS share sheet ("Open In…").
    func prepareOpenIn(romId: Int) {
        do {
            let resolved = try getDownloadedROMUseCase.execute(romId: romId)
            let result = getROMShareFilesUseCase.execute(rom: resolved.rom)
            guard !result.files.isEmpty else {
                downloadError = "No files available to open."
                return
            }
            shareItem = ShareURLsItem(urls: result.files, tempDirectory: result.tempDirectory)
        } catch {
            downloadError = error.localizedDescription
        }
    }

    /// Dismisses the share sheet.
    ///
    /// The temp copy is deliberately left behind: apps that open documents in
    /// place (RetroArch) still read from it while importing, and deleting it here
    /// would truncate the import. `GetROMShareFilesUseCase` collects old copies on
    /// the next share instead.
    func cleanupShareTemp() {
        shareItem = nil
    }

    // MARK: - External Emulator

    /// True when Play hands the ROM to another app instead of emulating it here.
    var playsExternally: Bool { playTarget.externalEmulator != nil }

    /// Re-reads the Play destination, e.g. after coming back from settings.
    func refreshPlayTarget() {
        playTarget = playTargetPreference.current
    }

    /// Routes a Play tap to the configured external emulator.
    ///
    /// The first launch has to go through the system "Open in" menu because iOS
    /// does not let us preselect a target; once the app has imported the ROM, its
    /// URL scheme boots it directly.
    ///
    /// - Returns: false when the built-in emulator should take over instead.
    func playExternally(rom: Rom) async -> Bool {
        guard let target = playTarget.externalEmulator else { return false }

        guard externalAppLauncher.isInstalled(target) else {
            errorMessage = "\(target.displayName) is not installed. Install it, or switch Play back to the built-in emulator in Settings."
            return true
        }

        guard let resolved = try? getDownloadedROMUseCase.execute(romId: rom.id) else {
            errorMessage = "Download this ROM before opening it in \(target.displayName)."
            return true
        }

        if externalEmulatorHandoffStore.hasHandedOff(romId: rom.id, to: target),
           let fileName = primaryFileName(of: resolved.rom) {
            if await externalAppLauncher.launch(target, fileName: fileName) {
                logger.info("Launched ROM \(rom.id) in \(target.displayName)")
                markPlayed(romId: rom.id)
                return true
            }
            // The app turned the link down, so its library no longer holds the
            // ROM. Hand it over again rather than leaving Play dead.
            logger.info("\(target.displayName) rejected the deep link, handing the ROM over again")
            externalEmulatorHandoffStore.forget(romId: rom.id)
        }

        await presentHandoff(of: resolved.rom, to: target)
        return true
    }

    /// Records that an "Open in" menu actually delivered the ROM, so the next Play
    /// tap can deep link instead of asking again.
    func handoffDidComplete(romId: Int, receivingBundleIdentifier: String) {
        guard let target = playTarget.externalEmulator else { return }
        guard target.matches(bundleIdentifier: receivingBundleIdentifier) else {
            logger.info("ROM \(romId) went to \(receivingBundleIdentifier), not \(target.displayName) — not remembered")
            return
        }
        externalEmulatorHandoffStore.markHandedOff(romId: romId, to: target)
        markPlayed(romId: romId)
    }

    /// No installed app claims this file type, so the "Open in" menu stayed empty.
    func handoffFoundNoTargets() {
        let name = playTarget.externalEmulator?.displayName ?? "the external emulator"
        errorMessage = "No app on this device can open this ROM. Make sure \(name) is installed and supports this file type."
        openInItem = nil
    }

    // MARK: - Private

    private func presentHandoff(of rom: DownloadedROM, to target: ExternalEmulator) async {
        // Handing a file over means copying it out of the ROM folder first, which
        // for a disc image is not instant. Show the Play spinner while it runs.
        isLaunchingEmulator = true
        await Task.yield()
        let result = getROMShareFilesUseCase.execute(rom: rom)
        isLaunchingEmulator = false

        guard !result.files.isEmpty else {
            errorMessage = "No files available to open."
            return
        }
        // The "Open in" menu carries a single document. Multi-file ROMs such as
        // cue/bin need every part, so those go through the share sheet, which the
        // user then has to point at the emulator themselves.
        if result.files.count == 1, let url = result.files.first {
            openInItem = OpenInItem(url: url, tempDirectory: result.tempDirectory)
        } else {
            shareItem = ShareURLsItem(urls: result.files, tempDirectory: result.tempDirectory)
        }
    }

    /// The file an external emulator should be pointed at.
    ///
    /// Disc-based ROMs ship a playlist or sheet next to the data tracks, and that
    /// is the file emulators expect — a raw `.bin` boots nothing.
    private func primaryFileName(of rom: DownloadedROM) -> String? {
        let preferredExtensions = ["m3u", "cue"]
        for ext in preferredExtensions {
            if let match = rom.files.first(where: { $0.fileName.lowercased().hasSuffix(".\(ext)") }) {
                return match.fileName
            }
        }
        return rom.files.first?.fileName
    }
}
