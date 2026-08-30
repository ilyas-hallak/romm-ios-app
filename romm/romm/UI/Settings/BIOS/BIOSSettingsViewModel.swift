import SwiftUI

@MainActor
final class BIOSSettingsViewModel: ObservableObject {
    @Published private(set) var sections: [Section] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    struct Section: Identifiable {
        let core: LibretroCore
        var statuses: [BIOSFileStatus]
        var id: String { core.rawValue }
    }

    private let useCase: PBIOSSyncUseCase
    private let cores: [LibretroCore] = [.pcsxRearmed, .flycast]

    init(useCase: PBIOSSyncUseCase) {
        self.useCase = useCase
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        var newSections: [Section] = []
        for core in cores {
            do {
                let statuses = try await useCase.loadStatuses(for: core)
                newSections.append(Section(core: core, statuses: statuses))
            } catch {
                errorMessage = error.localizedDescription
                newSections.append(Section(core: core, statuses: []))
            }
        }
        sections = newSections
    }

    func download(_ status: BIOSFileStatus, in core: LibretroCore) async {
        do {
            try await useCase.download(status: status, into: useCase.systemDirectory())
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
