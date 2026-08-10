//
//  PlatformDetailViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import Foundation
import Observation

enum PlatformDetailViewState {
    case loading
    case loaded([Rom])
    case loadingMore([Rom]) // Loading more data while showing current data
    case empty(String)
    case error(String)
}

@Observable
@MainActor
class PlatformDetailViewModel {
    var viewState: PlatformDetailViewState = .loading
    var charIndex: [String: Int] = [:] // A-Z index with counts
    var selectedChar: String? = nil // Currently selected character filter
    var lastLoadedRoms: [Rom] = [] // Keep last loaded ROMs for smooth transitions
    var viewMode: ViewMode = .smallCard
    
    var hasLoadedRoms: Bool {
        !lastLoadedRoms.isEmpty
    }
    
    func hasDataFor(platformId: Int) -> Bool {
        return currentPlatformId == platformId && hasLoadedRoms
    }
    
    var canLoadMore: Bool {
        hasMoreRoms
    }
    
    private let logger = Logger.viewModel
    private let romsUseCase: GetRomsUseCase
    private let romsWithFiltersUseCase: GetRomsWithFiltersUseCase
    private let getViewModeUseCase: PGetViewModeUseCase
    private let saveViewModeUseCase: PSaveViewModeUseCase
    private var currentOffset = 0
    private let pageSize = 72
    private var hasMoreRoms = true
    private var totalRoms = 0
    private var currentPlatformId: Int?
    private var currentChar: String?
    var currentOrderBy: String = "name"
    var currentOrderDir: String = "asc"

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.romsUseCase = factory.makeGetRomsUseCase()
        self.romsWithFiltersUseCase = factory.makeGetRomsWithFiltersUseCase()
        self.getViewModeUseCase = factory.makeGetViewModeUseCase()
        self.saveViewModeUseCase = factory.makeSaveViewModeUseCase()

        // Load saved sort preferences asynchronously
        Task {
            await loadSortPreferences()
        }

        loadViewMode()
    }

    private func loadSortPreferences() async {
        let asyncDefaults = AsyncUserDefaults.shared
        if let orderBy = await asyncDefaults.string(forKey: "selectedSortOrderBy") {
            currentOrderBy = orderBy
        }
        if let orderDir = await asyncDefaults.string(forKey: "selectedSortOrderDir") {
            currentOrderDir = orderDir
        }
    }

    func dismissError() {
        viewState = .empty("")
    }

    private func loadViewMode() {
        viewMode = getViewModeUseCase.execute()
    }

    func updateViewMode(_ newMode: ViewMode) {
        viewMode = newMode
        saveViewModeUseCase.execute(newMode)
    }
    
    func loadRoms(for platformId: Int, refresh: Bool = false) async {
        logger.info("Loading ROMs for platform \(platformId)")
        logger.debug("Platform ID being used: \(platformId)")
        
        if refresh {
            viewState = .loading
            currentOffset = 0
            hasMoreRoms = true
            totalRoms = 0
            charIndex = [:]
            selectedChar = nil
            lastLoadedRoms = [] // Clear cached ROMs on refresh
        }
        
        // Check if already loading (but allow first load)
        if case .loading = viewState, currentOffset > 0, !refresh {
            logger.debug("Already loading, skipping...")
            return
        }
        if case .loadingMore = viewState, !refresh {
            logger.debug("Already loading more, skipping...")
            return
        }
        
        guard hasMoreRoms else { return }
        
        // Set appropriate loading state - avoid full-screen loading if we have data
        if (currentOffset == 0 || refresh) && !hasLoadedRoms {
            // Only show full loading screen if we've never loaded anything
            viewState = .loading
        } else if hasLoadedRoms && (currentOffset == 0 || refresh) {
            // If we have data but are refreshing, keep showing data with indicator
            viewState = .loading // View will show content with loading indicator
        } else if case .loaded(let currentRoms) = viewState {
            viewState = .loadingMore(currentRoms)
        }
        currentPlatformId = platformId
        
        do {
            logger.debug("Fetching ROMs with offset \(currentOffset) for platform \(platformId)")
            let response = try await romsUseCase.execute(
                platformId: platformId,
                searchTerm: nil,
                limit: pageSize,
                offset: currentOffset,
                char: currentChar,
                orderBy: currentOrderBy,
                orderDir: currentOrderDir,
                collectionId: nil
            )
            
            let existingRoms: [Rom]
            
            // Handle existing ROMs based on current state
            switch viewState {
            case .loaded(let currentRoms), .loadingMore(let currentRoms):
                // Only append ROMs if this is a true pagination call (not character filtering)
                // Character filtering always starts fresh, even with currentOffset > 0
                let isCharacterFiltering = selectedChar != nil
                if !refresh && currentOffset > 0 && !isCharacterFiltering {
                    existingRoms = currentRoms
                    // Merge char indices for pagination
                    let processedIndex = processCharIndex(response.charIndex)
                    for (char, count) in processedIndex {
                        charIndex[char, default: 0] += count
                    }
                } else {
                    existingRoms = []
                    charIndex = processCharIndex(response.charIndex)
                }
            default:
                existingRoms = []
                charIndex = processCharIndex(response.charIndex)
            }
            
            let allRoms = existingRoms + response.roms

            if allRoms.isEmpty {
                viewState = .empty("No ROMs found for this platform")
            } else {
                viewState = .loaded(allRoms)
                lastLoadedRoms = allRoms // Update cached ROMs for smooth transitions
                prefetchCovers(for: response.roms)
            }

            currentOffset = response.offset + response.limit
            hasMoreRoms = response.hasMore
            totalRoms = response.total
            
            logger.info("Loaded \(response.roms.count) ROMs. Total: \(allRoms.count)/\(totalRoms), CharIndex: \(charIndex)")
        } catch {
            logger.error("Failed to load ROMs: \(error)")
            viewState = .error(error.localizedDescription)
        }
    }
    
    func loadMoreRomsIfNeeded() async {
        guard let platformId = currentPlatformId else { 
            logger.warning("No platform ID for load more")
            return 
        }
        
        // Only load more if we're not already loading and have more ROMs available
        guard case .loaded = viewState, hasMoreRoms else { 
            logger.debug("Skip load more - viewState: \(viewState), hasMore: \(hasMoreRoms)")
            return 
        }
        
        logger.debug("Loading more ROMs...")
        await loadRoms(for: platformId, refresh: false)
    }
    
    func refreshRoms() async {
        guard let platformId = currentPlatformId else { return }
        if let char = currentChar {
            await filterByChar(char, platformId: platformId)
        } else {
            await loadRoms(for: platformId, refresh: true)
        }
    }
    
    func searchRoms(query: String, platformId: Int) async {
        logger.info("Searching ROMs with query: '\(query)'")
        
        viewState = .loading
        charIndex = [:]
        currentOffset = 0
        
        do {
            let response = try await romsUseCase.execute(
                platformId: platformId,
                searchTerm: query.isEmpty ? nil : query,
                limit: pageSize,
                offset: 0,
                collectionId: nil
            )
            
            if response.roms.isEmpty {
                viewState = .empty(query.isEmpty ? "No ROMs found" : "No results for '\(query)'")
            } else {
                viewState = .loaded(response.roms)
                prefetchCovers(for: response.roms)
            }

            charIndex = processCharIndex(response.charIndex)
            hasMoreRoms = response.hasMore
            totalRoms = response.total
            currentOffset = response.offset + response.limit
            
            logger.info("Found \(response.roms.count) ROMs for query '\(query)' (Total: \(totalRoms), CharIndex: \(charIndex))")
        } catch {
            logger.error("Search failed: \(error)")
            viewState = .error(error.localizedDescription)
        }
    }
    
    func clearError() {
        if case .error = viewState {
            viewState = .loading
        }
    }
    
    func sortRoms(orderBy: String, orderDir: String) async {
        logger.info("Sorting ROMs by \(orderBy) \(orderDir)")

        currentOrderBy = orderBy
        currentOrderDir = orderDir

        // Persist sort settings asynchronously (fire and forget)
        Task.detached {
            let asyncDefaults = AsyncUserDefaults.shared
            await asyncDefaults.set(orderBy, forKey: "selectedSortOrderBy")
            await asyncDefaults.set(orderDir, forKey: "selectedSortOrderDir")
        }

        // Reload data with new sorting
        guard let platformId = currentPlatformId else { return }
        await loadRoms(for: platformId, refresh: true)
    }
    
    func applyFilters(_ filterStates: FilterStates, platformId: Int) async {
        logger.info("Applying filters to ROMs")
        
        let filters = RomFilters(
            matched: filterStates.showMatched ? true : nil,
            favourite: filterStates.showFavourites ? true : nil,
            duplicate: filterStates.showDuplicates ? true : nil,
            playable: nil,
            missing: filterStates.showMissing ? true : nil,
            hasRa: filterStates.showRetroAchievements ? true : nil,
            verified: filterStates.showVerified ? true : nil,
            selectedGenre: filterStates.selectedGenre,
            selectedFranchise: filterStates.selectedFranchise,
            selectedCollection: filterStates.selectedCollection,
            selectedCompany: filterStates.selectedCompany,
            selectedAgeRating: filterStates.selectedAgeRating,
            selectedStatus: filterStates.selectedStatus,
            selectedRegion: filterStates.selectedRegion,
            selectedLanguage: filterStates.selectedLanguage
        )
        logger.debug("Filter states converted - hasActiveFilters: \(filters.hasActiveFilters)")
        
        viewState = .loading
        charIndex = [:]
        currentOffset = 0
        hasMoreRoms = true
        
        do {
            let response = try await romsWithFiltersUseCase.execute(
                platformId: platformId,
                searchTerm: nil,
                limit: pageSize,
                offset: 0,
                char: nil,
                orderBy: "name", // Use safe default instead of currentOrderBy
                orderDir: "asc", // Use safe default instead of currentOrderDir
                collectionId: nil,
                filters: filters
            )
            
            if response.roms.isEmpty {
                viewState = .empty("No ROMs found matching your filters")
            } else {
                viewState = .loaded(response.roms)
                lastLoadedRoms = response.roms
                prefetchCovers(for: response.roms)
            }

            charIndex = processCharIndex(response.charIndex)
            hasMoreRoms = response.hasMore
            totalRoms = response.total
            currentOffset = response.offset + response.limit
            
            logger.info("Applied filters: \(response.roms.count) ROMs found (Total: \(totalRoms))")
        } catch {
            logger.error("Filter application failed: \(error)")
            viewState = .error(error.localizedDescription)
        }
    }
    
    func filterByChar(_ char: String?, platformId: Int) async {
        if char == nil {
            // Clear filter - load all ROMs
            logger.info("Clearing char filter - loading all ROMs")
            currentChar = nil
            selectedChar = nil
            await loadRoms(for: platformId, refresh: true)
        } else {
            // Apply char filter with offset-based jumping
            let apiChar = char == "#" ? "0" : char // Convert # back to 0 for API (representing 0-9)
            logger.info("Filtering ROMs by char: '\(char!)' (API: '\(apiChar!)')")
            
            // Use charIndex to jump directly to the character's position
            let rawOffset = charIndex[apiChar ?? ""] ?? 0
            let targetOffset = rawOffset // Use exact offset from server, no page alignment
            logger.debug("CharIndex lookup: '\(apiChar ?? "")' -> offset: \(targetOffset)")
            logger.debug("Available charIndex keys: \(Array(charIndex.keys).sorted())")
            logger.debug("Full charIndex: \(charIndex)")
            
            currentChar = nil // Don't pass char to API since it doesn't support it
            selectedChar = char // Keep UI selection as is
            currentPlatformId = platformId
            
            viewState = .loading
            currentOffset = targetOffset
            
            // Clear existing ROMs when filtering by character (not pagination)
            
            do {
                let response = try await romsUseCase.execute(
                    platformId: platformId,
                    searchTerm: nil,
                    limit: pageSize,
                    offset: targetOffset, // Use offset from charIndex
                    char: nil, // API doesn't support char filtering
                    collectionId: nil
                )
                
                if response.roms.isEmpty {
                    viewState = .empty("No ROMs found for '\(char!)'")
                } else {
                    viewState = .loaded(response.roms)
                    prefetchCovers(for: response.roms)
                }

                // Don't overwrite charIndex when filtering - keep original index for navigation
                // charIndex = processCharIndex(response.charIndex) // Keep original for char navigation
                hasMoreRoms = response.hasMore
                totalRoms = response.total
                currentOffset = response.offset + response.limit
                
                logger.info("Filtered \(response.roms.count) ROMs by char '\(char!)' (Total: \(totalRoms))")
                if let firstRom = response.roms.first {
                    logger.debug("First ROM returned: '\(firstRom.name)' (expected char: \(char!))")
                }
            } catch {
                logger.error("Char filter failed: \(error)")
                viewState = .error(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func processCharIndex(_ rawCharIndex: [String: Int]) -> [String: Int] {
        var processedIndex: [String: Int] = [:]
        
        for (char, count) in rawCharIndex {
            // Convert 0-9 to # for UI display
            if char.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                processedIndex["#", default: 0] += count
            } else {
                processedIndex[char] = count
            }
        }
        
        return processedIndex
    }

    private func prefetchCovers(for roms: [Rom]) {
        let urls = roms.compactMap { $0.urlCover }.compactMap { URL(string: $0) }
        KingfisherCacheManager.shared.preloadImages(urls: urls)
    }

    // MARK: - Helper Methods
}

// MARK: - Mock Data for Development
extension PlatformDetailViewModel {
    func loadMockRoms() {
        let mockRoms = [
            Rom(
                id: 1,
                name: "Super Mario Odyssey",
                slug: "super-mario-odyssey",
                summary: "A 3D platformer",
                platformId: 1,
                urlCover: nil,
                releaseYear: 2017,
                isFavourite: true,
                hasRetroAchievements: false,
                isPlayable: true
            ),
            Rom(
                id: 2,
                name: "The Legend of Zelda: Breath of the Wild",
                slug: "zelda-breath-of-the-wild",
                summary: "An adventure game",
                platformId: 1,
                urlCover: nil,
                releaseYear: 2017,
                isFavourite: false,
                hasRetroAchievements: true,
                isPlayable: true
            ),
            Rom(
                id: 3,
                name: "Mario Kart 8 Deluxe",
                slug: "mario-kart-8-deluxe",
                summary: "A racing game",
                platformId: 1,
                urlCover: nil,
                releaseYear: 2017,
                isFavourite: false,
                hasRetroAchievements: false,
                isPlayable: false
            )
        ]
        viewState = .loaded(mockRoms)
    }
}
