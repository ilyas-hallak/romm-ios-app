//
//  HomeViewModel.swift
//  romm
//

import Foundation
import Observation

@Observable
@MainActor
class HomeViewModel {
    var recentlyAdded: [Rom] = []
    var continuePlaying: [Rom] = []
    var platforms: [Platform] = []
    var collections: [Collection] = []

    var isLoadingRecentlyAdded = false
    var isLoadingContinuePlaying = false
    var isLoadingPlatforms = false
    var isLoadingCollections = false

    var hasStartedLoading = false

    private let getRomsWithFiltersUseCase: GetRomsWithFiltersUseCase
    private let getPlatformsUseCase: GetPlatformsUseCase
    private let getCollectionsUseCase: GetCollectionsUseCase
    private let tokenProvider: PTokenProvider

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getRomsWithFiltersUseCase = factory.makeGetRomsWithFiltersUseCase()
        self.getPlatformsUseCase = factory.makeGetPlatformsUseCase()
        self.getCollectionsUseCase = factory.makeGetCollectionsUseCase()
        self.tokenProvider = factory.tokenProvider
    }

    func coverURL(for collection: Collection) -> String? {
        if let url = collection.urlCover, !url.isEmpty { return url }
        guard let path = collection.pathCoversSmall.first, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return path }
        let base = tokenProvider.getServerURL()?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        return "\(base)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    func load() async {
        hasStartedLoading = true
        isLoadingRecentlyAdded = true
        isLoadingContinuePlaying = true
        isLoadingPlatforms = true
        isLoadingCollections = true

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchRecentlyAdded() }
            group.addTask { await self.fetchContinuePlaying() }
            group.addTask { await self.fetchPlatforms() }
            group.addTask { await self.fetchCollections() }
        }
    }

    private func fetchRecentlyAdded() async {
        do {
            let response = try await getRomsWithFiltersUseCase.execute(
                limit: 15,
                orderBy: "id",
                orderDir: "desc",
                filters: .empty
            )
            recentlyAdded = response.roms
        } catch {
            recentlyAdded = []
        }
        isLoadingRecentlyAdded = false
    }

    private func fetchContinuePlaying() async {
        do {
            let response = try await getRomsWithFiltersUseCase.execute(
                limit: 15,
                orderBy: "last_played",
                orderDir: "desc",
                filters: RomFilters(lastPlayed: true)
            )
            continuePlaying = response.roms
        } catch {
            continuePlaying = []
        }
        isLoadingContinuePlaying = false
    }

    private func fetchPlatforms() async {
        do {
            let all = try await getPlatformsUseCase.execute()
            platforms = all.filter { $0.romCount > 0 }
        } catch {
            platforms = []
        }
        isLoadingPlatforms = false
    }

    private func fetchCollections() async {
        do {
            let all = try await getCollectionsUseCase.execute()
            collections = all.filter { !$0.isVirtual }
        } catch {
            collections = []
        }
        isLoadingCollections = false
    }
}
