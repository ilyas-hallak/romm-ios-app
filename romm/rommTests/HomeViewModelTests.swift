import Testing
import Foundation
@testable import romm

// FakeAPIClient and its fixtures live in Support/FakeAPIClient.swift;
// MockDependencyFactory in Support/MockDependencyFactory.swift.

@MainActor
struct HomeViewModelTests {

    private func makeViewModel(api: FakeAPIClient) -> HomeViewModel {
        HomeViewModel(factory: MockDependencyFactory(apiClient: api))
    }

    @Test func loadShowsRecommendations() async {
        let api = FakeAPIClient()
        api.recommendationsToReturn = [
            RecommendedRomSchema(rom: makeSimpleRom(id: 10, name: "Chrono Trigger"), seedRomName: "Chrono Cross"),
            RecommendedRomSchema(rom: makeSimpleRom(id: 11, name: "Secret of Mana"), seedRomName: nil)
        ]
        let vm = makeViewModel(api: api)

        await vm.load()

        #expect(vm.recommendations.map(\.id) == [10, 11])
        #expect(vm.recommendations.map(\.seedRomName) == ["Chrono Cross", nil])
        #expect(vm.isLoadingRecommendations == false)
    }

    @Test func loadHidesRecommendationsWhenEndpointFails() async {
        let api = FakeAPIClient()
        api.recommendationsErrorToThrow = FakeAPIError()
        api.platformsToReturn = [
            makePlatform(id: 1, name: "Game Boy", slug: "gb", romCount: 12)
        ]
        let vm = makeViewModel(api: api)

        await vm.load()

        #expect(vm.recommendations.isEmpty)
        #expect(vm.isLoadingRecommendations == false)
        #expect(vm.platforms.map(\.id) == [1])
    }
}

