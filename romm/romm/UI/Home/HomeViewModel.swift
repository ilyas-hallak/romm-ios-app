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
    var isLoading: Bool = false
    var errorMessage: String?

    private let getRomsWithFiltersUseCase: GetRomsWithFiltersUseCase
    private let getPlatformsUseCase: GetPlatformsUseCase
    private let getCollectionsUseCase: GetCollectionsUseCase

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getRomsWithFiltersUseCase = factory.makeGetRomsWithFiltersUseCase()
        self.getPlatformsUseCase = factory.makeGetPlatformsUseCase()
        self.getCollectionsUseCase = factory.makeGetCollectionsUseCase()
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        async let recentTask = loadRecentlyAdded()
        async let continueTask = loadContinuePlaying()
        async let platformsTask = loadPlatforms()
        async let collectionsTask = loadCollections()

        let (recent, cont, plats, colls) = await (recentTask, continueTask, platformsTask, collectionsTask)

        recentlyAdded = recent
        continuePlaying = cont
        platforms = plats
        collections = colls

        isLoading = false
    }

    private func loadRecentlyAdded() async -> [Rom] {
        do {
            let response = try await getRomsWithFiltersUseCase.execute(
                limit: 15,
                orderBy: "id",
                orderDir: "desc",
                filters: .empty
            )
            return response.roms
        } catch {
            return []
        }
    }

    private func loadContinuePlaying() async -> [Rom] {
        do {
            let response = try await getRomsWithFiltersUseCase.execute(
                limit: 15,
                orderBy: "last_played",
                orderDir: "desc",
                filters: RomFilters(lastPlayed: true)
            )
            return response.roms
        } catch {
            return []
        }
    }

    private func loadPlatforms() async -> [Platform] {
        do {
            let all = try await getPlatformsUseCase.execute()
            return all.filter { $0.romCount > 0 }
        } catch {
            return []
        }
    }

    private func loadCollections() async -> [Collection] {
        do {
            let all = try await getCollectionsUseCase.execute()
            return all.filter { !$0.isVirtual }
        } catch {
            return []
        }
    }
}
