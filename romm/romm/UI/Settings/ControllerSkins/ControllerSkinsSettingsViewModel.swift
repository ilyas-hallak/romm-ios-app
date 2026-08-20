import SwiftUI

@MainActor
final class ControllerSkinsSettingsViewModel: ObservableObject {
    @Published private(set) var sections: [Section] = []
    @Published private(set) var isAdding = false
    /// Bound to the URL input field.
    @Published var urlText = ""
    @Published var errorMessage: String?

    // MARK: - Catalog-picker state

    @Published var skinChoices: [ControllerSkinLink] = []
    @Published var showChoicesSheet = false
    /// Per-link import state, keyed by the link's URL.
    @Published var skinImportStates: [URL: SkinLinkImportState] = [:]

    struct Section: Identifiable {
        let gameType: DeltaGameType
        var skins: [ControllerSkinInfo]
        var selectedSkin: ControllerSkinInfo?
        var id: String { gameType.rawValue }
    }

    private let useCase: PControllerSkinsUseCase

    init(useCase: PControllerSkinsUseCase) {
        self.useCase = useCase
    }

    func refresh() {
        do {
            let all = try useCase.skins()
            sections = buildSections(from: all)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addFromURL() async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = ControllerSkinError.invalidURL.localizedDescription
            return
        }
        isAdding = true
        defer { isAdding = false }
        do {
            let result = try await useCase.importSkin(from: url)
            errorMessage = nil
            switch result {
            case .imported(let skin):
                urlText = ""
                activate(skin)
            case .choices(let links):
                // Do not clear urlText yet - the user hasn't imported anything.
                skinChoices = links
                skinImportStates = [:]
                showChoicesSheet = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addFromFile(_ url: URL) {
        do {
            let skin = try useCase.addSkin(fromFileAt: url)
            errorMessage = nil
            activate(skin)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ skin: ControllerSkinInfo?, for gameType: DeltaGameType) {
        useCase.select(skin, forGameType: gameType.gameTypeIdentifier)
        // Update the section in-place without a full re-scan.
        if let idx = sections.firstIndex(where: { $0.gameType == gameType }) {
            sections[idx].selectedSkin = skin
        }
    }

    func delete(_ skin: ControllerSkinInfo) {
        do {
            try useCase.delete(skin)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Catalog-sheet actions

    func importLink(_ link: ControllerSkinLink) async {
        // Allow importing if not yet attempted, if ready, or if a previous attempt failed
        // (so the user can retry). Block only while loading or after a successful import.
        switch skinImportStates[link.url] {
        case nil, .ready, .failed:
            break
        case .loading, .imported:
            return
        }
        skinImportStates[link.url] = .loading
        do {
            let skin = try await useCase.addSkin(from: link)
            skinImportStates[link.url] = .imported(skin)
        } catch {
            skinImportStates[link.url] = .failed(error.localizedDescription)
        }
    }

    /// Called when the catalog sheet is dismissed.
    func onChoicesSheetDismissed() {
        let anyImported = skinImportStates.values.contains {
            if case .imported = $0 { return true }
            return false
        }
        if anyImported {
            urlText = ""
        }
        refresh()
        skinChoices = []
        skinImportStates = [:]
    }

    // MARK: - Private

    /// A freshly imported single skin becomes the active one right away.
    private func activate(_ skin: ControllerSkinInfo) {
        useCase.select(skin, forGameType: skin.gameTypeIdentifier)
        refresh()
    }

    private func buildSections(from skins: [ControllerSkinInfo]) -> [Section] {
        // Group by game type, skipping any unknown identifiers.
        var grouped: [DeltaGameType: [ControllerSkinInfo]] = [:]
        for skin in skins {
            guard let gameType = DeltaGameType(gameTypeIdentifier: skin.gameTypeIdentifier) else {
                continue
            }
            grouped[gameType, default: []].append(skin)
        }

        return grouped
            .filter { !$0.value.isEmpty }
            .map { gameType, skinList in
                let selected = useCase.selectedSkin(forGameType: gameType.gameTypeIdentifier)
                return Section(gameType: gameType, skins: skinList, selectedSkin: selected)
            }
            .sorted { $0.gameType.displayName < $1.gameType.displayName }
    }
}

// MARK: - Per-link import state

enum SkinLinkImportState: Equatable {
    case ready
    case loading
    case imported(ControllerSkinInfo)
    case failed(String)
}
