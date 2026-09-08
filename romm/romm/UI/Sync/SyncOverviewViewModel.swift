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
    /// has downloaded. Asking the server per row would cost a round trip each.
    private(set) var romNames: [Int: String] = [:]

    /// What was found in each external app's folder, keyed by app. Apart from
    /// `state`, since a granted folder is readable whether the server answers.
    private(set) var externalScans: [ExternalEmulatorID: ExternalSaveScan] = [:]

    private let previewUseCase: PSyncPreviewUseCase
    private let getDownloadedROM: PGetDownloadedROMUseCase
    private let scanExternalSaves: PScanExternalSavesUseCase
    private let setupStore: PExternalEmulatorSetupStore

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.getDownloadedROM = factory.makeGetDownloadedROMUseCase()
        self.scanExternalSaves = factory.makeScanExternalSavesUseCase()
        self.setupStore = factory.externalEmulatorSetupStore
    }

    /// Starts in a given state, for previews: every state this screen shows
    /// needs a server that is in it. Loading only runs from `.idle`.
    init(
        showing state: State,
        romNames: [Int: String] = [:],
        externalScans: [ExternalEmulatorID: ExternalSaveScan] = [:],
        factory: PDependencyFactory = DefaultDependencyFactory.shared
    ) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.getDownloadedROM = factory.makeGetDownloadedROMUseCase()
        self.scanExternalSaves = factory.makeScanExternalSavesUseCase()
        self.setupStore = factory.externalEmulatorSetupStore
        self.state = state
        self.romNames = romNames
        self.externalScans = externalScans
    }

    /// The apps this screen reports on: set up, and with a locatable save
    /// layout. Anything else would be a source the user cannot act on here.
    var externalSources: [ExternalEmulatorID] {
        setupStore.configuredEmulators().filter { $0.emulator.saveLayout != nil }
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var preview: SyncPreview? {
        if case .loaded(let preview) = state { return preview }
        return nil
    }

    func load() async {
        // Local and quick, and still meaningful when the request below fails.
        rescanExternalFolders()

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

    func rescanExternalFolders() {
        externalScans = Dictionary(
            uniqueKeysWithValues: scanExternalSaves.executeForAllGranted().map { ($0.emulator, $0) }
        )
    }

    /// The name to show for a ROM, falling back to its id for a save another
    /// device pushed for a game this one never downloaded.
    func displayName(forRom romId: Int) -> String {
        // As text, since interpolating the Int formats it for the locale and
        // turns 4711 into "4.711" in German.
        romNames[romId] ?? String(localized: "ROM \(String(romId))")
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
