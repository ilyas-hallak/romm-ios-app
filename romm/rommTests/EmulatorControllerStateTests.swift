#if !APP_STORE
import Combine
import Foundation
import Testing
@testable import romm

@MainActor
struct EmulatorControllerStateTests {
    @Test(arguments: [false, true])
    func disconnectedControllerKeepsTouchControlsVisible(alwaysShowTouchControls: Bool) {
        #expect(!EmulatorControllerState.shouldHideTouchControls(
            isConnected: false,
            alwaysShowTouchControls: alwaysShowTouchControls
        ))
    }

    @Test func connectedControllerHidesTouchControlsByDefault() {
        #expect(EmulatorControllerState.shouldHideTouchControls(
            isConnected: true,
            alwaysShowTouchControls: false
        ))
    }

    @Test func overrideKeepsTouchControlsVisibleAlongsideController() {
        #expect(!EmulatorControllerState.shouldHideTouchControls(
            isConnected: true,
            alwaysShowTouchControls: true
        ))
    }

    @Test func absentPreferenceUsesAutomaticVisibility() throws {
        try withIsolatedDefaults { defaults in
            #expect(!EmulatorControllerState.alwaysShowTouchControls(in: defaults))
        }
    }

    @Test func existingPreferenceUsesThePersistedKey() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(true, forKey: "emulator.alwaysShowTouchControls")
            #expect(EmulatorControllerState.alwaysShowTouchControls(in: defaults))
        }
    }

    @Test func overridePersistsAcrossDefaultsInstances() throws {
        let suite = "EmulatorControllerStateTests-\(UUID().uuidString)"
        let first = try #require(UserDefaults(suiteName: suite))
        defer { first.removePersistentDomain(forName: suite) }
        let notifications = NotificationCenter()

        EmulatorControllerState.setAlwaysShowTouchControls(
            true, userDefaults: first, notificationCenter: notifications
        )
        let second = try #require(UserDefaults(suiteName: suite))
        #expect(EmulatorControllerState.alwaysShowTouchControls(in: second))
        EmulatorControllerState.setAlwaysShowTouchControls(
            false, userDefaults: second, notificationCenter: notifications
        )
        #expect(!EmulatorControllerState.alwaysShowTouchControls(in: first))
    }

    @Test func visibilityNotificationSeesTheUpdatedPreferenceAndSkipsUnchangedValues() throws {
        try withIsolatedDefaults { defaults in
            let notifications = NotificationCenter()
            var observedValues: [Bool] = []
            let observation = notifications.publisher(for: .emulatorTouchControlsVisibilityChanged)
                .sink { _ in
                    observedValues.append(EmulatorControllerState.alwaysShowTouchControls(in: defaults))
                }
            defer { observation.cancel() }

            EmulatorControllerState.setAlwaysShowTouchControls(
                false, userDefaults: defaults, notificationCenter: notifications
            )
            #expect(observedValues.isEmpty)
            #expect(defaults.object(forKey: "emulator.alwaysShowTouchControls") == nil)

            EmulatorControllerState.setAlwaysShowTouchControls(
                true, userDefaults: defaults, notificationCenter: notifications
            )
            #expect(observedValues == [true])
            EmulatorControllerState.setAlwaysShowTouchControls(
                true, userDefaults: defaults, notificationCenter: notifications
            )
            #expect(observedValues == [true])

            EmulatorControllerState.setAlwaysShowTouchControls(
                false, userDefaults: defaults, notificationCenter: notifications
            )
            #expect(observedValues == [true, false])
        }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "EmulatorControllerStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
#endif
