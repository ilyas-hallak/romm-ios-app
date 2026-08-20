import SwiftUI

@MainActor
final class ControllerSkinsSettingsViewModel: ObservableObject {
    @Published private(set) var sections: [Section] = []
    @Published private(set) var isAdding = false
    /// Bound to the URL input field.
    @Published var urlText = ""
    @Published var errorMessage: String?

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
            let skin = try await useCase.addSkin(from: url)
            urlText = ""
            errorMessage = nil
            activate(skin)
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

    // MARK: - Private

    /// Someone who just imported a skin wants to use it, so a fresh import
    /// becomes the active one for its system right away.
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
