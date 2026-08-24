import Foundation

/// An emulator app outside of RomM that a downloaded ROM can be handed off to.
///
/// Handing a ROM over takes two steps: iOS does not let us preselect a target in
/// the share sheet, so the first launch goes through the system "Open in" menu
/// and every later one uses the target app's own URL scheme.
enum ExternalEmulator: String, CaseIterable, Codable, Sendable {
    case retroarch

    var displayName: String {
        switch self {
        case .retroarch: return "RetroArch"
        }
    }

    /// Scheme used both for the installation check and for the deep link. It has
    /// to be listed in `LSApplicationQueriesSchemes` or `canOpenURL` always says no.
    var urlScheme: String {
        switch self {
        case .retroarch: return "retroarch"
        }
    }

    var probeURL: URL? {
        URL(string: "\(urlScheme)://")
    }

    /// Deep link that boots a ROM the target app has already imported.
    ///
    /// RetroArch resolves `retroarch://game/<name.ext>` against its own library,
    /// so the plain file name is the identifier and nothing has to be hashed.
    func launchURL(fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        switch self {
        case .retroarch:
            var components = URLComponents()
            components.scheme = urlScheme
            components.host = "game"
            components.path = "/\(fileName)"
            return components.url
        }
    }

    /// Whether an app that just received a document is this emulator.
    ///
    /// `UIDocumentInteractionController` reports the receiving bundle identifier,
    /// which is the only reliable signal that the handoff actually happened.
    /// RetroArch ships under several identifiers (`com.libretro.RetroArch`,
    /// `…RetroArchiOS11`, plus ad-hoc builds), so match on the substring.
    func matches(bundleIdentifier: String) -> Bool {
        switch self {
        case .retroarch: return bundleIdentifier.lowercased().contains("retroarch")
        }
    }
}

/// Where a Play tap sends the user.
enum PlayTarget: Hashable, Sendable {
    case builtIn
    case external(ExternalEmulator)

    var externalEmulator: ExternalEmulator? {
        if case .external(let emulator) = self { return emulator }
        return nil
    }
}
