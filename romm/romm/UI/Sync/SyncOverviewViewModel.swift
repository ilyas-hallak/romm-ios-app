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

    /// What was found in each external app's folder, keyed by app.
    ///
    /// Kept apart from `state`, which is about the server: a granted folder is
    /// readable whether or not the server answers, and hiding what is on the
    /// device behind a failed request would be the wrong way round.
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

    /// Starts in a given state, for previews.
    ///
    /// Every state this screen can show needs a server that is in that state,
    /// which is the one thing a preview cannot arrange. Loading is skipped
    /// because it only runs from `.idle`.
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

    /// The apps this screen reports on: the ones set up, whose saves can be
    /// located at all.
    ///
    /// Only configured apps, because setting one up now happens in settings.
    /// Listing an app that was never added would offer a source the user cannot
    /// act on from here.
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
        // The folders are read first and on their own: they are local, they are
        // quick, and they stay meaningful when the request below fails.
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

    /// The name to show for a ROM, falling back to its id when this device has
    /// never downloaded it. That happens for a save another device pushed, which
    /// is exactly the row a user is least likely to recognise, so the id is
    /// spelled out rather than left blank.
    func displayName(forRom romId: Int) -> String {
        // The id goes in as text: interpolating the Int formats it for the
        // locale, which turned ROM 4711 into "ROM 4.711" in German.
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
