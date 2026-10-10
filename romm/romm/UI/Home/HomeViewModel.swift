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

    var isLoadingRecentlyAdded = true
    var isLoadingContinuePlaying = true
    var isLoadingPlatforms = true
    var isLoadingCollections = true

    var hasStartedLoading = false

    /// Shows the one-time "sign in again to upload" hint; set by
    /// `checkUploadSignInHint()`, cleared once the user answers either button.
    var showUploadSignInAlert = false
    /// The check costs a request, so it runs once per session rather than on
    /// every return to Home.
    private var hasCheckedUploadSignInHint = false

    private let getRomsWithFiltersUseCase: GetRomsWithFiltersUseCase
    private let getPlatformsUseCase: GetPlatformsUseCase
    private let getCollectionsUseCase: GetCollectionsUseCase
    private let getRomUploadAvailabilityUseCase: GetRomUploadAvailabilityUseCase
    private let clearSetupConfigurationUseCase: PClearSetupConfigurationUseCase
    private let signInHintStore: PRomUploadSignInHintStore
    private let tokenProvider: PTokenProvider

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getRomsWithFiltersUseCase = factory.makeGetRomsWithFiltersUseCase()
        self.getPlatformsUseCase = factory.makeGetPlatformsUseCase()
        self.getCollectionsUseCase = factory.makeGetCollectionsUseCase()
        self.getRomUploadAvailabilityUseCase = factory.makeGetRomUploadAvailabilityUseCase()
        self.clearSetupConfigurationUseCase = factory.makeClearSetupConfigurationUseCase()
        self.signInHintStore = factory.romUploadSignInHintStore
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
        prefetchCovers()
    }

    /// Shows the upload sign-in hint at most once per installation. Only ever
    /// turns `showUploadSignInAlert` on for `.missingScope`; every other
    /// availability (including a failed check) leaves the hint unmarked, so an
    /// account that is simply not allowed to upload, or a server that answers
    /// later, still gets a fair chance to show it.
    func checkUploadSignInHint() async {
        guard !hasCheckedUploadSignInHint, !signInHintStore.hasShownMissingScopeHint else { return }
        hasCheckedUploadSignInHint = true
        let availability = await getRomUploadAvailabilityUseCase.execute()
        guard availability == .missingScope else { return }
        showUploadSignInAlert = true
    }

    /// "Sign In Again" on the hint. Same composition as
    /// `ProfileViewModel.restartSetup()` and `RomUploadSheetViewModel.signInAgain()`.
    func signInAgainForUpload() {
        signInHintStore.markMissingScopeHintShown()
        try? clearSetupConfigurationUseCase.execute()
        NotificationCenter.default.post(name: .restartSetupRequested, object: nil)
    }

    /// "Not Now" on the hint: just stop asking again.
    func dismissUploadSignInHint() {
        signInHintStore.markMissingScopeHintShown()
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

    private func prefetchCovers() {
        var urls = (recentlyAdded + continuePlaying).compactMap { $0.listCoverURL }.compactMap { URL(string: $0) }
        urls += collections.compactMap { coverURL(for: $0) }.compactMap { URL(string: $0) }
        KingfisherCacheManager.shared.preloadImages(urls: urls)
    }
}
