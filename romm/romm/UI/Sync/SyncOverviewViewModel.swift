import Foundation

@Observable
@MainActor
final class SyncOverviewViewModel {

    enum State {
        case idle
        case loading
        case loaded(SyncPreview)
        case failed(SyncPreviewError)
    }

    private(set) var state: State = .idle

    /// Names for the ROMs an operation refers to, resolved from what this device
    /// has downloaded. A plan that reads "ROM 4711" tells the user nothing, and
    /// asking the server for each name would put a round trip per row between
    /// the tap and the answer.
    private(set) var romNames: [Int: String] = [:]

    private let previewUseCase: PSyncPreviewUseCase
    private let getDownloadedROM: PGetDownloadedROMUseCase

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.getDownloadedROM = factory.makeGetDownloadedROMUseCase()
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    func load() async {
        state = .loading
        do {
            let preview = try await previewUseCase.execute()
            romNames = resolveNames(for: preview)
            state = .loaded(preview)
        } catch let error as SyncPreviewError {
            state = .failed(error)
        } catch {
            state = .failed(.negotiationFailed(error.localizedDescription))
        }
    }

    /// The name to show for a ROM, falling back to its id when this device has
    /// never downloaded it. That happens for a save another device pushed, which
    /// is exactly the row a user is least likely to recognise, so the id is
    /// spelled out rather than left blank.
    func displayName(forRom romId: Int) -> String {
        romNames[romId] ?? String(localized: "ROM \(romId)")
    }

    private func resolveNames(for preview: SyncPreview) -> [Int: String] {
        let romIds = Set(preview.operations.map { $0.romId })
        return romIds.reduce(into: [Int: String]()) { names, romId in
            if let resolved = try? getDownloadedROM.execute(romId: romId) {
                names[romId] = resolved.rom.name
            }
        }
    }
}
