import Foundation

/// The Bonjour service the two sides find each other by. Also listed under
/// `NSBonjourServices` in Info.plist, iOS blocks the browse otherwise.
enum RemoteControllerBonjour {
    static let serviceType = "_romm-pad._tcp"
    static let domain = "local."
}
