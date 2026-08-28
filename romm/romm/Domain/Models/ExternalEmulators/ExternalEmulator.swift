import Foundation

/// An emulator app outside of RomM that a downloaded ROM can be handed off to.
///
/// Handing a ROM over takes two steps: iOS does not let us preselect a target in
/// the share sheet, so the first launch goes through the system "Open in" menu
/// and every later one uses the target app's own URL scheme.
///
/// Implementations describe a target app and stay free of file access, so they
/// remain synchronously testable. Deriving the identifier a target app uses can
/// mean reading and hashing a whole ROM, which is
/// `ResolveExternalGameIdentifierUseCase`'s job instead.
protocol PExternalEmulator: Sendable {
    var id: ExternalEmulatorID { get }
    var displayName: String { get }
    /// Scheme used both for the installation check and for the deep link. It has
    /// to be listed in `LSApplicationQueriesSchemes` or `canOpenURL` always says no.
    var urlScheme: String { get }
    /// How this app addresses a ROM it has already imported.
    var identifierKind: ExternalGameIdentifierKind { get }
    /// Whether the handoff has to carry the plain ROM rather than the archive it
    /// is stored in.
    var wantsUnpackedROM: Bool { get }
    /// Whether an app that just received a document is this emulator.
    ///
    /// `UIDocumentInteractionController` reports the receiving bundle identifier,
    /// which is the only reliable signal that the handoff actually happened.
    func matches(bundleIdentifier: String) -> Bool
    /// Deep link that boots a ROM the target app has already imported.
    func launchURL(gameIdentifier: String) -> URL?
}

extension PExternalEmulator {
    var probeURL: URL? {
        URL(string: "\(urlScheme)://")
    }

    /// Both supported apps resolve a game as `<scheme>://game/<identifier>`, they
    /// only disagree on what the identifier is.
    func launchURL(gameIdentifier: String) -> URL? {
        guard !gameIdentifier.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "game"
        components.path = "/\(gameIdentifier)"
        return components.url
    }
}

/// Stable identity of a supported emulator app.
///
/// The raw values are persistence keys: they end up in the Play target
/// preference and in the handoff store's UserDefaults keys, so renaming a case
/// silently resets the user's choice.
enum ExternalEmulatorID: String, CaseIterable, Codable, Sendable {
    case retroarch
    case delta

    /// The behaviour behind this identity.
    ///
    /// Deliberately a `switch` rather than a registry array: adding a case
    /// without wiring it up then fails to compile instead of resolving to nil at
    /// runtime.
    var emulator: any PExternalEmulator {
        switch self {
        case .retroarch: return RetroArchExternalEmulator()
        case .delta: return DeltaExternalEmulator()
        }
    }
}

/// How a target app addresses a ROM it has already imported.
///
/// The kind, not the emulator, is what a resolved identifier is cached under:
/// the SHA-1 of a ROM is the same no matter which app asks for it.
enum ExternalGameIdentifierKind: String, CaseIterable, Sendable {
    /// The plain file name, nothing has to be read or hashed.
    case fileName
    /// Lowercase hex SHA-1 over the whole ROM file.
    case sha1OfROMData
}
