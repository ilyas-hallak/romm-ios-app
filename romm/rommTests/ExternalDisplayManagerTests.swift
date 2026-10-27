import Testing
@testable import romm

/// Covers `setPhoneControllerOnlyEnabled`, the one setter on the manager that
/// mirrors a preference into a `@Published` property, which is the mechanism
/// behind the toggle applying without a relaunch.
@MainActor
struct ExternalDisplayManagerTests {

    @Test func settingPhoneControllerOnlyWritesThePreferenceAndThePublishedProperty() {
        let preference = InMemoryExternalDisplayPreference()
        let manager = ExternalDisplayManager(preference: preference, diagnostics: DiagnosticsSpy())

        manager.setPhoneControllerOnlyEnabled(true)

        #expect(preference.isPhoneControllerOnlyEnabled == true)
        #expect(manager.isPhoneControllerOnlyEnabled == true)
    }

    @Test func initReadsTheStartingValueFromThePreference() {
        let preference = InMemoryExternalDisplayPreference()
        preference.isPhoneControllerOnlyEnabled = true

        let manager = ExternalDisplayManager(preference: preference, diagnostics: DiagnosticsSpy())

        #expect(manager.isPhoneControllerOnlyEnabled == true)
    }
}
