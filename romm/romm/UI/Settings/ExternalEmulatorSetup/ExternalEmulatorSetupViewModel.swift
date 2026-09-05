import Foundation

@Observable
@MainActor
final class ExternalEmulatorSetupViewModel {

    /// Where the assistant currently is.
    enum Stage: Equatable {
        /// Nothing picked yet, the list of apps is showing.
        case choosingApp
        /// Working through the steps for the picked app.
        case step(ExternalEmulatorSetupStep)
        case finished
    }

    private(set) var stage: Stage = .choosingApp
    private(set) var emulator: ExternalEmulatorID?
    private(set) var plan: ExternalEmulatorSetupPlan?
    private(set) var completedSteps: Set<ExternalEmulatorSetupStep> = []

    /// What the folder step found, so the user gets an answer rather than a
    /// silent dismissal.
    private(set) var folderScan: ExternalSaveScan?
    /// ROMs offered for the test run.
    private(set) var testableROMs: [DownloadedROM] = []
    private(set) var testResult: TestResult?

    var errorMessage: String?

    enum TestResult: Equatable {
        case handedOver(romName: String)
        case failed(String)
    }

    private let launcher: PExternalAppLauncher
    private let folderStore: PExternalSaveFolderStore
    private let setupStore: PExternalEmulatorSetupStore
    private let scanUseCase: PScanExternalSavesUseCase
    private let localROMs: PLocalROMRepository
    private let playTargetPreference: PPlayTargetPreference

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.launcher = factory.externalAppLauncher
        self.folderStore = factory.externalSaveFolderStore
        self.setupStore = factory.externalEmulatorSetupStore
        self.scanUseCase = factory.makeScanExternalSavesUseCase()
        self.localROMs = factory.localROMRepository
        self.playTargetPreference = factory.playTargetPreference
    }

    /// Apps that can still be added, so an already configured one is not offered
    /// twice.
    var addableEmulators: [ExternalEmulatorID] {
        ExternalEmulatorID.allCases.filter { !setupStore.isConfigured($0) }
    }

    func isInstalled(_ emulator: ExternalEmulatorID) -> Bool {
        launcher.isInstalled(emulator.emulator)
    }

    // MARK: - Flow

    func choose(_ emulator: ExternalEmulatorID) {
        self.emulator = emulator
        let plan = ExternalEmulatorSetupPlan(
            emulator: emulator,
            isInstalled: isInstalled(emulator),
            hasSaveFolder: folderStore.grantedFolder(for: emulator) != nil
        )
        self.plan = plan
        completedSteps = []
        stage = plan.steps.first.map { .step($0) } ?? .finished
    }

    /// Re-checks installation, for coming back from the App Store.
    func refreshInstallState() {
        guard let emulator, case .step(.install) = stage, isInstalled(emulator) else { return }
        advance()
    }

    func advance() {
        guard let plan, case .step(let current) = stage else { return }
        completedSteps.insert(current)
        guard let index = plan.steps.firstIndex(of: current),
              plan.steps.indices.contains(index + 1) else {
            finish()
            return
        }
        stage = .step(plan.steps[index + 1])
        if case .testRun = plan.steps[index + 1] { loadTestableROMs() }
    }

    func skipCurrentStep() {
        guard case .step(let current) = stage, current.isSkippable else { return }
        advance()
    }

    /// Marks the app as set up and makes it the Play target, which is what the
    /// user came here to do.
    private func finish() {
        if let emulator {
            setupStore.markConfigured(emulator)
            playTargetPreference.current = .external(emulator)
        }
        stage = .finished
    }

    // MARK: - Steps

    func openAppStore() {
        // Nothing here can install an app; this only gets the user to where they
        // can, and `refreshInstallState` picks it up when they come back.
        guard let emulator, let url = emulator.emulator.probeURL else { return }
        Task { _ = await launcher.open(emulator.emulator) }
        _ = url
    }

    func grantFolder(_ url: URL) {
        guard let emulator else { return }
        do {
            try folderStore.remember(folderURL: url, for: emulator)
            folderScan = try? scanUseCase.execute(for: emulator)
        } catch {
            errorMessage = String(
                localized: "Could not keep access to that folder: \(error.localizedDescription)"
            )
        }
    }

    private func loadTestableROMs() {
        // Only downloaded ROMs can be handed over, and the list is capped
        // because this is a confidence check, not a library browser.
        testableROMs = Array(((try? localROMs.getAllDownloadedROMs()) ?? []).prefix(30))
    }

    /// Records how the test run went. The handoff itself is driven by the shared
    /// coordinator, which owns the presentation it needs.
    func recordTestResult(_ result: TestResult) {
        testResult = result
    }
}
