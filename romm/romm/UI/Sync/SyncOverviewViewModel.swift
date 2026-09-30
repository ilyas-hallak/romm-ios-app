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

    enum ApplyState {
        case idle
        case running(completed: Int, total: Int)
        /// The plan was applied and is spent: its session is closed on the
        /// server, so getting on from here means negotiating again.
        case finished(SyncApplyReport)
    }

    private(set) var state: State = .idle

    /// Names for the ROMs an operation refers to, resolved from what this device
    /// has downloaded. Asking the server per row would cost a round trip each.
    private(set) var romNames: [Int: String] = [:]

    /// What was found in each external app's folder, keyed by app. Apart from
    /// `state`, since a granted folder is readable whether the server answers.
    private(set) var externalScans: [ExternalEmulatorID: ExternalSaveScan] = [:]

    /// Applying is its own state, so the plan stays on screen while it runs and
    /// the report can be shown against the rows it is about.
    private(set) var applyState: ApplyState = .idle

    /// Which side the user picked, per conflicting operation. Absent means
    /// undecided, and an undecided conflict is left alone: overwriting a save
    /// nobody chose to lose is the one outcome this screen must not produce.
    private(set) var resolutions: [UUID: SyncConflictResolution] = [:]

    private let previewUseCase: PSyncPreviewUseCase
    private let applyUseCase: PApplySyncUseCase
    private let getDownloadedROM: PGetDownloadedROMUseCase
    private let scanExternalSaves: PScanExternalSavesUseCase
    private let setupStore: PExternalEmulatorSetupStore

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.applyUseCase = factory.makeApplySyncUseCase()
        self.getDownloadedROM = factory.makeGetDownloadedROMUseCase()
        self.scanExternalSaves = factory.makeScanExternalSavesUseCase()
        self.setupStore = factory.externalEmulatorSetupStore
    }

    /// Starts in a given state, for previews: every state this screen shows
    /// needs a server that is in it. Loading only runs from `.idle`, and a
    /// finished sync cannot be reached by running one against a stub.
    init(
        showing state: State,
        applyState: ApplyState = .idle,
        resolutions: [UUID: SyncConflictResolution] = [:],
        romNames: [Int: String] = [:],
        externalScans: [ExternalEmulatorID: ExternalSaveScan] = [:],
        factory: PDependencyFactory = DefaultDependencyFactory.shared
    ) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.applyUseCase = factory.makeApplySyncUseCase()
        self.getDownloadedROM = factory.makeGetDownloadedROMUseCase()
        self.scanExternalSaves = factory.makeScanExternalSavesUseCase()
        self.setupStore = factory.externalEmulatorSetupStore
        self.state = state
        self.applyState = applyState
        self.resolutions = resolutions
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

    var isApplying: Bool {
        if case .running = applyState { return true }
        return false
    }

    var applyReport: SyncApplyReport? {
        if case .finished(let report) = applyState { return report }
        return nil
    }

    /// True while there is a plan worth applying that has not been applied yet.
    var canApply: Bool {
        guard case .loaded(let preview) = state, case .idle = applyState else { return false }
        return !preview.isUpToDate
    }

    /// Conflicts still waiting on the user. Shown as a count so the button can
    /// say what applying now would leave behind.
    var unresolvedConflictCount: Int {
        preview?.conflicts.filter { resolutions[$0.id] == nil }.count ?? 0
    }

    /// The scans in a fixed order, so the same folders produce the same request
    /// twice running rather than one that varies with dictionary order.
    private var orderedScans: [ExternalSaveScan] {
        externalScans.values.sorted { $0.emulator.rawValue < $1.emulator.rawValue }
    }

    func load() async {
        // Local and quick, and still meaningful when the request below fails.
        rescanExternalFolders()

        state = .loading
        do {
            let preview = try await previewUseCase.execute(externalScans: orderedScans)
            romNames = resolveNames(for: preview)
            state = .loaded(preview)
        } catch let error as SyncPreviewError {
            state = .failed(error)
        } catch {
            state = .failed(.negotiationFailed(error.localizedDescription))
        }
    }

    /// Records which side of a conflict wins. Overwrites an earlier choice, so
    /// the user can change their mind up until applying.
    func resolve(_ operation: SyncPreviewOperation, as resolution: SyncConflictResolution) {
        guard case .idle = applyState else { return }
        resolutions[operation.id] = resolution
    }

    func resolution(for operation: SyncPreviewOperation) -> SyncConflictResolution? {
        resolutions[operation.id]
    }

    /// Applies the plan on screen, exactly as shown rather than re-negotiated:
    /// the user agreed to this one.
    func apply() async {
        guard case .loaded(let preview) = state, case .idle = applyState else { return }

        applyState = .running(completed: 0, total: preview.operations.count)
        let report = await applyUseCase.execute(
            preview: preview,
            resolutions: resolutions,
            progress: { [weak self] completed, total in
                self?.applyState = .running(completed: completed, total: total)
            }
        )
        applyState = .finished(report)

        // The folders have changed under us, and what they now hold is what the
        // report is about.
        rescanExternalFolders()
    }

    /// Negotiates again after a finished sync, which is the only way on: the
    /// applied plan's session is closed and its saves have moved.
    func reload() async {
        applyState = .idle
        resolutions = [:]
        state = .idle
        await load()
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
