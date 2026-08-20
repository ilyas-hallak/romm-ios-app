import Foundation

/// Which controller skin to use per system. Keyed by Delta game type identifier;
/// no entry means the core's built-in standard skin.
protocol PControllerSkinPreference: AnyObject {
    func selectedFileName(forGameType gameTypeIdentifier: String) -> String?
    func setSelectedFileName(_ fileName: String?, forGameType gameTypeIdentifier: String)
}
