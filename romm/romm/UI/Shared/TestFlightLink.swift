import UIKit

enum TestFlightLink {
    private static let testFlight = URL(string: "itms-beta://")!
    private static let appStore = URL(string: "https://apps.apple.com/app/testflight/id899247664")!

    /// Opens the TestFlight app, falling back to its App Store page when it is not
    /// installed. `canOpenURL` for itms-beta needs LSApplicationQueriesSchemes, so we
    /// just attempt the open and use the completion handler as the probe.
    @MainActor
    static func open() {
        UIApplication.shared.open(testFlight, options: [:]) { success in
            if !success {
                UIApplication.shared.open(appStore)
            }
        }
    }
}
