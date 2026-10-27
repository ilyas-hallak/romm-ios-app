//
//  CollectionDetailViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 10.08.25.
//

import Foundation
import Observation

@Observable
@MainActor
class CollectionDetailViewModel {
    private let logger = Logger.viewModel
    var viewState: RomViewState = .loading
    var charIndex: [String: Int] = [:]
    var selectedChar: String? = nil
    var currentOrderBy: String = "name"
    var currentOrderDir: String = "asc"
    var canLoadMore: Bool = false
    
    private let getRomsUseCase: GetRomsUseCase
    private var collectionId: Int
    private var currentRoms: [Rom] = []
    private var currentLimit: Int = 50
    private var currentOffset: Int = 0
    private var totalRoms: Int = 0
    
    enum RomViewState {
        case loading
        case loaded([Rom])
        case loadingMore([Rom])
        case empty(String)
        case error(String)
    }
    
    init(collectionId: Int, factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.collectionId = collectionId
        self.getRomsUseCase = factory.makeGetRomsUseCase()
    }

    func dismissError() {
        viewState = .empty("")
    }
    
    func loadRoms() async {
        guard case .loading = viewState else { return }
        
        do {
            let response = try await getRomsUseCase.execute(
                platformId: nil,
                searchTerm: nil,
                limit: currentLimit,
                offset: 0,
                char: nil,
                orderBy: currentOrderBy,
                orderDir: currentOrderDir,
                collectionId: collectionId
            )
            
            currentRoms = response.roms
            totalRoms = response.total
            currentOffset = response.roms.count
            canLoadMore = response.hasMore
            charIndex = response.charIndex
            prefetchCovers(for: response.roms)
            
            if response.roms.isEmpty {
                viewState = .empty("This collection contains no ROMs")
            } else {
                viewState = .loaded(response.roms)
            }
            
            logger.info("Loaded \(response.roms.count) ROMs for collection \(collectionId)")
        } catch {
            viewState = .error(error.localizedDescription)
            logger.error("Error loading collection ROMs: \(error)")
        }
    }
    
    func refreshRoms() async {
        currentRoms = []
        currentOffset = 0
        viewState = .loading
        await loadRoms()
    }
    
    func loadMoreRomsIfNeeded() async {
        guard canLoadMore,
              case .loaded(let currentRoms) = viewState else { return }
        
        viewState = .loadingMore(currentRoms)
        
        do {
            let response = try await getRomsUseCase.execute(
                platformId: nil,
                searchTerm: nil,
                limit: currentLimit,
                offset: currentOffset,
                char: selectedChar,
                orderBy: currentOrderBy,
                orderDir: currentOrderDir,
                collectionId: collectionId
            )
            
            let allRoms = self.currentRoms + response.roms
            self.currentRoms = allRoms
            self.currentOffset = allRoms.count
            self.canLoadMore = response.hasMore
            prefetchCovers(for: response.roms)
            
            viewState = .loaded(allRoms)
            
            logger.info("Loaded \(response.roms.count) more ROMs. Total: \(allRoms.count)")
        } catch {
            viewState = .error(error.localizedDescription)
            logger.error("Error loading more ROMs: \(error)")
        }
    }
    
    func filterByChar(_ char: String?) async {
        selectedChar = char
        currentOffset = 0
        currentRoms = []
        viewState = .loading
        
        do {
            let response = try await getRomsUseCase.execute(
                platformId: nil,
                searchTerm: nil,
                limit: currentLimit,
                offset: 0,
                char: char,
                orderBy: currentOrderBy,
                orderDir: currentOrderDir,
                collectionId: collectionId
            )
            
            currentRoms = response.roms
            currentOffset = response.roms.count
            canLoadMore = response.hasMore
            prefetchCovers(for: response.roms)
            
            if response.roms.isEmpty {
                let message = char != nil ? "No ROMs found starting with '\(char!)'" : "This collection contains no ROMs"
                viewState = .empty(message)
            } else {
                viewState = .loaded(response.roms)
            }
            
            logger.info("Filtered by char '\(char ?? "none")': \(response.roms.count) ROMs")
        } catch {
            viewState = .error(error.localizedDescription)
            logger.error("Error filtering ROMs by char: \(error)")
        }
    }
    
    func sortRoms(orderBy: String, orderDir: String) async {
        currentOrderBy = orderBy
        currentOrderDir = orderDir
        currentOffset = 0
        currentRoms = []
        viewState = .loading
        
        do {
            let response = try await getRomsUseCase.execute(
                platformId: nil,
                searchTerm: nil,
                limit: currentLimit,
                offset: 0,
                char: selectedChar,
                orderBy: orderBy,
                orderDir: orderDir,
                collectionId: collectionId
            )
            
            currentRoms = response.roms
            currentOffset = response.roms.count
            canLoadMore = response.hasMore
            prefetchCovers(for: response.roms)
            
            if response.roms.isEmpty {
                viewState = .empty("This collection contains no ROMs")
            } else {
                viewState = .loaded(response.roms)
            }
            
            logger.info("Sorted by \(orderBy) \(orderDir): \(response.roms.count) ROMs")
        } catch {
            viewState = .error(error.localizedDescription)
            logger.error("Error sorting ROMs: \(error)")
        }
    }

    private func prefetchCovers(for roms: [Rom]) {
        let urls = roms.compactMap { $0.listCoverURL }.compactMap { URL(string: $0) }
        KingfisherCacheManager.shared.preloadImages(urls: urls)
    }
}
