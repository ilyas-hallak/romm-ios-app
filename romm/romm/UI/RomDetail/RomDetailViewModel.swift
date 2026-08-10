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
        print("[RomDetailVM] launchEmulator tapped for rom id=\(rom.id)")
        // Check if experimental feature is enabled first
        guard ExperimentalFeatureSettings.shared.isEmulatorEnabled else {
            print("[RomDetailVM] experimental emulator disabled — showing hint")
            showingEmulatorFeatureHint = true
            return
        }

        isLaunchingEmulator = true
        let result = await launchEmulatorUseCase.execute(rom: rom)

        switch result {
        case .success(let decision):
            logger.info("Launching emulator for ROM: \(rom.name) — decision: \(String(describing: decision))")
            self.launchDecision = decision
            Task { [updateLastPlayedUseCase, logger] in
                do {
                    try await updateLastPlayedUseCase.execute(romId: rom.id)
                } catch {
                    logger.warning("Failed to update last_played for ROM \(rom.id): \(error)")
                }
            }

        case .failure(let error):
            logger.error("Failed to launch emulator: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isLaunchingEmulator = false
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

    /// Cleans up the temporary directory created for sharing.
    func cleanupShareTemp() {
        if let dir = shareItem?.tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        shareItem = nil
    }
}
