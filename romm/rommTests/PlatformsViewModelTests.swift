import Testing
import Foundation
@testable import romm

// FakeAPIClient, the makePlatform fixture and FakeAPIError live in
// Support/FakeAPIClient.swift; MockDependencyFactory in Support/MockDependencyFactory.swift.
//
// These are the first ViewModel tests: they prove a ViewModel can be driven
// entirely through injected test doubles, with no real network request. The
// MockDependencyFactory builds a real PlatformsRepository against the fake
// client, so the full ViewModel -> use case -> repository -> API chain runs.

@MainActor
struct PlatformsViewModelTests {

    private func makeViewModel(api: FakeAPIClient) -> PlatformsViewModel {
        PlatformsViewModel(factory: MockDependencyFactory(apiClient: api))
    }

    @Test func loadPlatformsPopulatesStateFromClient() async {
        let api = FakeAPIClient()
        api.platformsToReturn = [
            makePlatform(id: 1, name: "Game Boy", slug: "gb", romCount: 12),
            makePlatform(id: 2, name: "Super Nintendo", slug: "snes", romCount: 30)
        ]
        let vm = makeViewModel(api: api)

        await vm.loadPlatforms()

        #expect(vm.platforms.map(\.id) == [1, 2])
        #expect(vm.platforms.map(\.name) == ["Game Boy", "Super Nintendo"])
        #expect(vm.platforms.first?.romCount == 12)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadPlatformsSurfacesErrorAndKeepsListEmpty() async {
        let api = FakeAPIClient()
        api.errorToThrow = FakeAPIError()
        let vm = makeViewModel(api: api)

        await vm.loadPlatforms()

        #expect(vm.platforms.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage != nil)
    }

    @Test func loadPlatformsWithEmptyResponseLeavesNoError() async {
        let api = FakeAPIClient()
        api.platformsToReturn = []
        let vm = makeViewModel(api: api)

        await vm.loadPlatforms()

        #expect(vm.platforms.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    @Test func addPlatformRejectsEmptyInputWithoutHittingClient() {
        let api = FakeAPIClient()
        let vm = makeViewModel(api: api)

        vm.addPlatform(name: "", slug: "")

        #expect(vm.errorMessage == "Platform name and slug cannot be empty")
        #expect(api.addPlatformCallCount == 0)
    }
}
