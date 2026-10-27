import Foundation
import UIKit

/// Holds the remote pad between the network and whichever engine is running.
///
/// Shared, like `ExternalDisplayManager`: the pad connects from Settings or from
/// the login screen, long before a game exists, and has to survive every game
/// that starts and ends after that. A running session registers itself as the
/// input and takes it back down when it stops.
@MainActor
final class SecondControllerManager: ObservableObject {

    static let shared = SecondControllerManager(
        hostService: RemoteControllerHostService(),
        preference: UserDefaultsSecondControllerPreferenceStore()
    )

    /// Name of the pad currently playing, `nil` while none is connected.
    @Published private(set) var padName: String?

    var isPadConnected: Bool { padName != nil }

    private let hostService: PRemoteControllerHostService
    private let preference: PSecondControllerPreference
    private weak var input: PSecondPlayerInput?

    init(hostService: PRemoteControllerHostService, preference: PSecondControllerPreference) {
        self.hostService = hostService
        self.preference = preference
        hostService.onButton = { [weak self] button, pressed in
            self?.input?.setSecondPlayerButton(button, pressed: pressed)
        }
        hostService.onPadChanged = { [weak self] name in
            guard let self else { return }
            self.padName = name
            self.input?.setSecondPlayerConnected(name != nil)
        }
    }

    // MARK: - Advertising

    var acceptsRemotePad: Bool { preference.acceptsRemotePad }

    /// Called at launch, so a phone that was set up once keeps taking pads.
    func startIfEnabled() {
        guard preference.acceptsRemotePad else { return }
        hostService.startAdvertising(as: UIDevice.current.name)
    }

    func setAcceptsRemotePad(_ enabled: Bool) {
        preference.acceptsRemotePad = enabled
        if enabled {
            hostService.startAdvertising(as: UIDevice.current.name)
        } else {
            hostService.stopAdvertising()
        }
    }

    // MARK: - The running game

    /// The session takes the pad while it runs and hands it back when it stops.
    /// A pad that is already connected is announced right away, so a game
    /// started after the pad joined still finds it.
    func setInput(_ input: PSecondPlayerInput?) {
        self.input?.setSecondPlayerConnected(false)
        self.input = input
        input?.setSecondPlayerConnected(isPadConnected)
    }
}
