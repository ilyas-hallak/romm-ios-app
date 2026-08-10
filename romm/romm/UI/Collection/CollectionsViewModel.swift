//
//  CollectionsViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 10.08.25.
//

import Foundation
import os
import Observation

enum CollectionViewState {
    case loading
    case empty
    case loaded
    case loadingMore
}

@Observable
@MainActor
class CollectionsViewModel {
    private let logger = Logger.viewModel
    var collections: [Collection] = []
    var virtualCollections: [VirtualCollection] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var showingCreateCollection: Bool = false
    var collectionToDelete: Collection?
    var isDeleting: Bool = false
    var canLoadMoreCollections: Bool = true
    var isLoadingMore: Bool = false
    private var hasLoadedOnce: Bool = false

    var viewState: CollectionViewState {
        if isLoading && !hasLoadedOnce {
            return .loading
        } else if collections.isEmpty && virtualCollections.isEmpty && hasLoadedOnce {
            return .empty
        } else if isLoadingMore {
            return .loadingMore
        } else {
            return .loaded
        }
    }

    private let getCollectionsUseCase: GetCollectionsUseCase
    private let getVirtualCollectionsUseCase: GetVirtualCollectionsUseCase
    private let deleteCollectionUseCase: DeleteCollectionUseCase
    private let tokenProvider: PTokenProvider

    // Pagination state
    private var currentCollectionOffset = 0
    private let collectionsPageSize = 20

    // Task management to prevent cancellations
    private var loadTask: Task<Void, Never>?
    
    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getCollectionsUseCase = factory.makeGetCollectionsUseCase()
        self.getVirtualCollectionsUseCase = factory.makeGetVirtualCollectionsUseCase()
        self.deleteCollectionUseCase = factory.makeDeleteCollectionUseCase()
        self.tokenProvider = factory.tokenProvider

        // Don't load automatically - prevents UI blocking during tab switches
        // View will trigger loading via .task or .onAppear modifier
    }
    
    func coverURL(for collection: Collection) -> String? {
        if let url = collection.urlCover, !url.isEmpty { return url }
        guard let path = collection.pathCoversSmall.first, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return path }
        let base = tokenProvider.getServerURL()?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        return "\(base)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    func loadCollections() async {
        // If we already have data, don't reload
        if hasLoadedOnce && !collections.isEmpty || !virtualCollections.isEmpty {
            logger.info("Collections already loaded, skipping")
            return
        }

        // If already loading, wait for existing task
        if let existingTask = loadTask {
            logger.info("Load already in progress, waiting...")
            await existingTask.value
            return
        }

        // Start new load task
        loadTask = Task {
            await performLoad()
        }

        await loadTask?.value
        loadTask = nil
    }

    private func performLoad() async {
        // Cancel any existing loading task
        resetPagination()

        isLoading = true
        errorMessage = nil

        do {
            // Load collections first with pagination, then virtual collections sequentially to avoid conflicts
            logger.info("Loading initial collections...")
            let loadedCollections = try await getCollectionsUseCase.execute(
                limit: collectionsPageSize,
                offset: 0
            )

            // Check if cancelled before continuing
            try Task.checkCancellation()

            logger.info("Loading virtual collections...")
            let loadedVirtualCollections = try await getVirtualCollectionsUseCase.execute(type: "all", limit: 10)

            // Check if cancelled before updating UI
            try Task.checkCancellation()

            self.collections = loadedCollections
            self.virtualCollections = loadedVirtualCollections
            self.currentCollectionOffset = 0
            self.canLoadMoreCollections = loadedCollections.count == self.collectionsPageSize
            self.isLoading = false
            self.hasLoadedOnce = true
            prefetchCovers()

            logger.info("✅ Loaded \(loadedCollections.count) collections and \(loadedVirtualCollections.count) virtual collections")

        } catch is CancellationError {
            logger.info("Collection loading cancelled")
            self.isLoading = false
            // Don't update hasLoadedOnce on cancellation
        } catch {
            self.isLoading = false
            self.hasLoadedOnce = true
            self.errorMessage = error.localizedDescription
            logger.error("❌ Error loading collections: \(error)")
        }
    }
    
    func refreshCollections() async {
        guard !isLoading else { return }
        
        // Cancel any existing loading task and start fresh
        resetPagination()
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Load collections sequentially to avoid conflicts
            logger.info("Refreshing collections...")
            let loadedCollections = try await getCollectionsUseCase.execute(
                limit: collectionsPageSize,
                offset: 0
            )
            
            logger.info("Refreshing virtual collections...")
            let loadedVirtualCollections = try await getVirtualCollectionsUseCase.execute(type: "all", limit: 10)
            
            self.collections = loadedCollections
            self.virtualCollections = loadedVirtualCollections
            self.currentCollectionOffset = 0
            self.canLoadMoreCollections = loadedCollections.count == self.collectionsPageSize
            self.isLoading = false
            prefetchCovers()

            logger.info("✅ Refreshed \(loadedCollections.count) collections and \(loadedVirtualCollections.count) virtual collections")
            
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            logger.error("❌ Error refreshing collections: \(error)")
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Collection Creation
    
    func showCreateCollection() {
        showingCreateCollection = true
    }
    
    func hideCreateCollection() {
        showingCreateCollection = false
    }
    
    func onCollectionCreated(_ collection: Collection) {
        // Add the new collection to the list immediately for better UX
        collections.insert(collection, at: 0)
        logger.info("✅ New collection added to list: \(collection.name)")
        
        // Note: We don't refresh here to avoid overwriting the newly added item
        // The list will be refreshed on the next app launch or manual refresh
    }
    
    // MARK: - Collection Deletion
    
    func showDeleteConfirmation(for collection: Collection) {
        collectionToDelete = collection
    }
    
    func hideDeleteConfirmation() {
        collectionToDelete = nil
    }
    
    func deleteCollection(_ collection: Collection) async {
        guard !isDeleting else { return }
        
        isDeleting = true
        errorMessage = nil
        
        do {
            try await deleteCollectionUseCase.execute(collectionId: collection.id)
            
            // Remove from local list immediately
            collections.removeAll { $0.id == collection.id }
            hideDeleteConfirmation()
            
            logger.info("✅ Collection deleted: \(collection.name)")
            
        } catch {
            errorMessage = error.localizedDescription
            logger.error("❌ Error deleting collection: \(error)")
        }
        
        isDeleting = false
    }
    
    // MARK: - Pagination
    
    func loadMoreCollectionsIfNeeded() async {
        guard canLoadMoreCollections && !isLoadingMore && !isLoading else { 
            logger.info("Skipping loadMore: canLoad=\(canLoadMoreCollections), isLoadingMore=\(isLoadingMore), isLoading=\(isLoading)")
            return 
        }
        
        isLoadingMore = true
        
        do {
            logger.info("Loading more collections from offset \(currentCollectionOffset + collectionsPageSize)...")
            
            // Load more collections with pagination
            let moreCollections = try await getCollectionsUseCase.execute(
                limit: collectionsPageSize,
                offset: currentCollectionOffset + collectionsPageSize
            )
            
            if moreCollections.isEmpty {
                canLoadMoreCollections = false
                logger.info("No more collections to load")
            } else {
                // Append new collections to existing ones
                collections.append(contentsOf: moreCollections)
                currentCollectionOffset += collectionsPageSize
                prefetchCovers()

                logger.info("✅ Loaded \(moreCollections.count) more collections. Total: \(collections.count)")
            }
            
        } catch {
            logger.error("❌ Error loading more collections: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoadingMore = false
    }

    private func prefetchCovers() {
        let urls = collections.compactMap { coverURL(for: $0) }.compactMap { URL(string: $0) }
        KingfisherCacheManager.shared.preloadImages(urls: urls)
    }

    private func resetPagination() {
        currentCollectionOffset = 0
        canLoadMoreCollections = true
        isLoadingMore = false
    }
}
