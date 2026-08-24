import Foundation

protocol PGetCachedUpdateUseCase {
    func execute() -> AvailableUpdate?
}

/// Restores the result of an earlier check so the banner can appear right away
/// instead of after a round trip. Carries no entries: only the build number is
/// cached, a fresh check fills in the rest.
final class GetCachedUpdateUseCase: PGetCachedUpdateUseCase {
    private let repository: PChangelogRepository
    private let stateStore: PUpdateCheckStateStore

    init(repository: PChangelogRepository, stateStore: PUpdateCheckStateStore) {
        self.repository = repository
        self.stateStore = stateStore
    }

    func execute() -> AvailableUpdate? {
        guard let cached = stateStore.cachedPublishedBuild,
              cached > repository.installedBuild,
              cached != stateStore.dismissedBuild else { return nil }

        return AvailableUpdate(build: cached, version: "?", date: nil, entries: [])
    }
}
