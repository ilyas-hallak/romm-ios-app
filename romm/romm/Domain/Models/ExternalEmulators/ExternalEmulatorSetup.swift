import Foundation

/// Remembers which emulator apps the user has finished setting up.
///
/// Being installed is not the same as being set up: the app also has to be
/// understood (how a ROM gets there) and, for syncing, pointed at a folder.
/// Without this the settings list could only offer every installed app at once,
/// which is what it used to do and why nothing explained the Manic handoff.
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
        // Unknown values are skipped rather than dropped from storage: a build
        // that no longer knows an app should not erase the user's setup for a
        // build that does.
        stored.compactMap(ExternalEmulatorID.init(rawValue:))
    }
}

/// One step of setting up an emulator app.
///
/// Which steps apply depends on the app and on what is already true, so the
/// sequence is worked out rather than fixed: an installed app skips the install
/// step, and an app whose saves cannot be located has no folder step.
enum ExternalEmulatorSetupStep: Equatable, Hashable {
    /// The app is not on the device yet.
    case install
    /// How a ROM gets into this app the first time, which differs per app and is
    /// the step that stops Manic from looking broken.
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
    /// Only the steps that ask for something: pointing at a folder, handing a
    /// ROM over. A user who does not want save syncing should not be blocked
    /// from playing, and a test run needs a downloaded ROM that may not exist.
    ///
    /// Reading is not one of them. The handoff step asks for nothing, so a skip
    /// next to Continue would be a second button doing the same thing, and
    /// install cannot be skipped at all.
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
        // An app whose save layout is unknown has nothing to point at, so
        // offering a folder picker would ask the user for something that cannot
        // be used.
        if emulator.emulator.saveLayout != nil, !hasSaveFolder { steps.append(.saveFolder) }
        steps.append(.testRun)
        self.steps = steps
    }
}
