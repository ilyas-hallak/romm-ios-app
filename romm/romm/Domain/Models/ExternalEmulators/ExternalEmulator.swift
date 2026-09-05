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
    /// The route a ROM takes into this app on its first handoff.
    var romDelivery: ExternalROMDelivery { get }
    /// How this app names and files the battery saves it writes, or nil when
    /// that is not known well enough to go looking for them.
    var saveLayout: ExternalSaveLayout? { get }
    /// ROM extensions this app accepts on platforms the built-in engines have no
    /// `DeltaGameType` for, or nil to support only the platforms they do.
    ///
    /// Only consulted as a fallback: a known platform resolves through its game
    /// type, which is narrower and therefore picks the right file on ROMs that
    /// ship several. Archive extensions must stay out, or the handoff would pass
    /// the archive and hash that instead of what the target app unpacks from it.
    var romExtensions: Set<String>? { get }
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

    /// Most targets only handle what the built-in engines handle.
    var romExtensions: Set<String>? { nil }

    /// The "Open in" menu is the only route that reports which app took the file,
    /// so it stays the default and anything else has to opt out deliberately.
    var romDelivery: ExternalROMDelivery { .openInMenu }

    /// Saves are only read out of an app that has described where it writes them.
    var saveLayout: ExternalSaveLayout? { nil }

    /// What the user has to do the first time a ROM goes to this app.
    ///
    /// Worth saying out loud during setup, because the first handoff is the one
    /// step this app cannot complete on the user's behalf, and an app that
    /// silently waits for a paste looks like a Play button that does nothing.
    var handoffExplanation: String {
        switch romDelivery {
        case .openInMenu:
            return String(localized: "The first time you play a game, pick \(displayName) from the share sheet that appears. After that it opens there straight away.")
        case .pasteboard:
            return String(localized: "\(displayName) cannot take games from the share sheet, so the first time you play one it goes to the clipboard instead. Open \(displayName) and paste it to add it to your library. After that it opens there straight away.")
        }
    }

    /// Every supported app resolves a game as `<scheme>://game/<identifier>`, they
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
    case manicEmu = "manicemu"

    /// The behaviour behind this identity.
    ///
    /// Deliberately a `switch` rather than a registry array: adding a case
    /// without wiring it up then fails to compile instead of resolving to nil at
    /// runtime.
    var emulator: any PExternalEmulator {
        switch self {
        case .retroarch: return RetroArchExternalEmulator()
        case .delta: return DeltaExternalEmulator()
        case .manicEmu: return ManicEmuExternalEmulator()
        }
    }
}

/// How a ROM gets from here into a target app that has not seen it before.
enum ExternalROMDelivery: Sendable {
    /// The system "Open in" menu, which copies the file into the target's inbox
    /// and tells us which app took it.
    case openInMenu
    /// The general pasteboard, carrying the file as an `NSItemProvider`. The user
    /// has to paste it in the target app, so the handoff cannot be confirmed.
    case pasteboard
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
    /// djb2 over the ROM's hex SHA-256, as a decimal string. Manic EMU's shortened
    /// content hash, see `FileHashing.manicGameID`.
    case manicGameID
}
