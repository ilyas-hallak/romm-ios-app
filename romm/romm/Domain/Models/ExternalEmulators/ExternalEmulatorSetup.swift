import Foundation

/// Remembers which emulator apps the user has finished setting up.
///
/// Being installed is not the same as being set up: the user also has to know
/// how a ROM gets there and, for syncing, point at a save folder. Only apps
/// that have been through setup are offered as a Play target.
protocol PExternalEmulatorSetupStore: AnyObject {
    func isConfigured(_ emulator: ExternalEmulatorID) -> Bool
    func markConfigured(_ emulator: ExternalEmulatorID)
    func forget(_ emulator: ExternalEmulatorID)
    /// In the order they were added, so the settings list does not reshuffle.
    func configuredEmulators() -> [ExternalEmulatorID]
}

final class UserDefaultsExternalEmulatorSetupStore: PExternalEmulatorSetupStore {

    private let key = "externalEmulator.configured"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    private var stored: [String] {
        get { userDefaults.stringArray(forKey: key) ?? [] }
        set { userDefaults.set(newValue, forKey: key) }
    }

    func isConfigured(_ emulator: ExternalEmulatorID) -> Bool {
        stored.contains(emulator.rawValue)
    }

    func markConfigured(_ emulator: ExternalEmulatorID) {
        guard !isConfigured(emulator) else { return }
        stored.append(emulator.rawValue)
    }

    func forget(_ emulator: ExternalEmulatorID) {
        stored.removeAll { $0 == emulator.rawValue }
    }

    func configuredEmulators() -> [ExternalEmulatorID] {
        // Skipped rather than dropped from storage: a build that no longer
        // knows an app must not erase the setup for a build that does.
        stored.compactMap(ExternalEmulatorID.init(rawValue:))
    }
}

/// One step of setting up an emulator app.
///
/// The sequence is worked out per app rather than fixed: an installed app skips
/// the install step, one with no known save layout has no folder step.
enum ExternalEmulatorSetupStep: Equatable, Hashable {
    /// The app is not on the device yet.
    case install
    /// How a ROM gets into this app the first time, which differs per app.
    case handoff
    /// Point at the folder its saves live in, so they can be synced.
    case saveFolder
    /// Hand a real ROM over once and see whether it arrives.
    case testRun

    var title: String {
        switch self {
        case .install: return String(localized: "Install the app")
        case .handoff: return String(localized: "How games get there")
        case .saveFolder: return String(localized: "Find its saves")
        case .testRun: return String(localized: "Try it once")
        }
    }

    /// Whether this step offers a way past it besides doing it.
    ///
    /// Only the two that ask for something: a user who does not want save
    /// syncing must not be blocked from playing, and a test run needs a
    /// downloaded ROM that may not exist. The steps that only explain something
    /// have nothing to skip.
    var isSkippable: Bool {
        self == .saveFolder || self == .testRun
    }
}

/// Works out what still has to happen for one app.
struct ExternalEmulatorSetupPlan: Equatable {
    let emulator: ExternalEmulatorID
    let steps: [ExternalEmulatorSetupStep]

    init(emulator: ExternalEmulatorID, isInstalled: Bool, hasSaveFolder: Bool) {
        self.emulator = emulator
        var steps: [ExternalEmulatorSetupStep] = []
        if !isInstalled { steps.append(.install) }
        steps.append(.handoff)
        // Nothing to point at without a known layout, so no folder step.
        if emulator.emulator.saveLayout != nil, !hasSaveFolder { steps.append(.saveFolder) }
        steps.append(.testRun)
        self.steps = steps
    }
}
