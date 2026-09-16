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

    /// Set once a run finishes, cleared again the next time one starts.
    private(set) var lastSyncReport: SaveSyncReport?
    private(set) var isSyncing = false

    private let previewUseCase: PSyncPreviewUseCase
    private let getDownloadedROM: PGetDownloadedROMUseCase
    private let scanExternalSaves: PScanExternalSavesUseCase
    private let setupStore: PExternalEmulatorSetupStore
    private let syncRunner: PSaveSyncRunner

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.getDownloadedROM = factory.makeGetDownloadedROMUseCase()
        self.scanExternalSaves = factory.makeScanExternalSavesUseCase()
        self.setupStore = factory.externalEmulatorSetupStore
        self.syncRunner = factory.makeSaveSyncRunner()
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
        self.syncRunner = factory.makeSaveSyncRunner()
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

    /// Whether "Sync Now" has anything to try. A loaded plan is enough on its
    /// own: `SaveSyncRunner.run` always syncs save states for every ROM this
    /// device holds anything for regardless of the plan (states are never
    /// part of it, see `SyncPreviewUseCase`), so a battery-only plan that is
    /// already up to date with no matching external file can still turn up
    /// state work. A run that truly finds nothing to do is harmless, the
    /// report just says so.
    var canSyncNow: Bool {
        preview != nil && !isSyncing
    }

    /// One line describing what the last run did, or nil before any run.
    var lastSyncSummary: String? {
        guard let report = lastSyncReport else { return nil }
        if report.uploaded == 0, report.downloaded == 0, report.skippedConflicts == 0,
           report.skipped == 0, report.failed == 0 {
            return String(localized: "Nothing to sync, everything is up to date.")
        }
        var parts = [
            String(localized: "\(report.uploaded) uploaded"),
            String(localized: "\(report.downloaded) downloaded")
        ]
        if report.skippedConflicts > 0 {
            parts.append(String(localized: "\(report.skippedConflicts) conflicts left"))
        }
        if report.skipped > 0 {
            parts.append(String(localized: "\(report.skipped) skipped"))
        }
        var summary = parts.joined(separator: ", ")
        if report.failed > 0 {
            summary += " " + String(localized: "(\(report.failed) failed)")
        }
        return summary
    }

    /// What the last run did with one app's saves, for its row. Empty until a
    /// run actually had that app's files in hand: whether a file is newer than
    /// the server's copy is only known once the run has listed them.
    func lastSyncDetail(for emulator: ExternalEmulatorID) -> String {
        guard let outcome = lastSyncReport?.externalApps[emulator] else { return "" }
        if outcome.failed > 0 {
            return String(localized: "\(outcome.failed) failed")
        }
        if outcome.uploaded > 0 {
            return String(localized: "\(outcome.uploaded) uploaded")
        }
        return String(localized: "Up to date")
    }

    func lastSyncFailed(for emulator: ExternalEmulatorID) -> Bool {
        (lastSyncReport?.externalApps[emulator]?.failed ?? 0) > 0
    }

    /// The last run's failure messages, capped so one bad run cannot flood the
    /// screen. Empty when the last run had no failures, or there was no run yet.
    var lastSyncErrors: [String] {
        guard let report = lastSyncReport, !report.errors.isEmpty else { return [] }
        let shown = Array(report.errors.prefix(3))
        let remaining = report.errors.count - shown.count
        guard remaining > 0 else { return shown }
        return shown + [String(localized: "and \(remaining) more")]
    }

    /// Runs the plan for real, then reloads it so the screen reflects the new
    /// state rather than the one it was computed against.
    func syncNow() async {
        guard let preview, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        lastSyncReport = await syncRunner.run(preview: preview, externalScans: externalScans)
        await load()
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
