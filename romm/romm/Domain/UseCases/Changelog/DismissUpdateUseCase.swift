import Foundation

protocol PDismissUpdateUseCase {
    /// Hides the hint for this build. A newer one brings it back.
    func execute(build: Int)
}

final class DismissUpdateUseCase: PDismissUpdateUseCase {
    private let stateStore: PUpdateCheckStateStore

    init(stateStore: PUpdateCheckStateStore) {
        self.stateStore = stateStore
    }

    func execute(build: Int) {
        stateStore.dismissedBuild = build
    }
}
