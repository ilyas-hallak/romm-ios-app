import Foundation

/// Provenance keys an imported game on the MD5 of its ROM and resolves
/// `provenance://open?md5=<md5>` against that, so the identifier has to be
/// computed from the file's contents rather than its name.
///
/// Like Delta it hashes the ROM it ends up with rather than the archive it came
/// in, so the handoff unpacks first and passes the plain ROM rather than
/// guessing which entry Provenance would pick.
struct ProvenanceExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .provenance }
    var displayName: String { "Provenance" }
    var urlScheme: String { "provenance" }
    var appStoreURL: URL? { URL(string: "https://apps.apple.com/app/id1596862805") }
    var identifierKind: ExternalGameIdentifierKind { .md5OfROMData }
    var wantsUnpackedROM: Bool { true }

    /// Battery saves land under `Battery States/<system>/<ROM name>.srm`, so the
    /// hint stops above the per-system directory, which is not one value. `sav`
    /// alongside `srm` because Provenance runs both libretro cores, which write
    /// the libretro extension, and its own, which do not.
    ///
    /// Save states are left out: they sit in a sibling `Save States` folder as
    /// `.svs` plus a JSON side-car, which is not a battery save and not
    /// something `ExternalSaveLayout` describes.
    var saveLayout: ExternalSaveLayout? {
        ExternalSaveLayout(
            naming: .romBaseName,
            batteryExtensions: ["srm", "sav"],
            searchHints: ["Battery States"]
        )
    }

    /// The share sheet leaves the ROM in `Documents/Imports`, where a directory
    /// watcher picks it up. Nothing reports when that finished and the game is
    /// not started, which the setup assistant has to say out loud.
    var handoffExplanation: String {
        String(localized: "The first time you play a game, pick \(displayName) from the share sheet that appears. \(displayName) imports it in the background without starting it, so open that one game from its library yourself. After that it opens there straight away.")
    }

    /// Nightly and sideloaded builds append to the bundle id, so match the prefix.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix("org.provenance-emu.provenance")
    }

    /// Provenance reads the identifier out of the query rather than the path,
    /// so the shared `<scheme>://game/<id>` form does not resolve here.
    func launchURL(gameIdentifier: String) -> URL? {
        guard !gameIdentifier.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "md5", value: gameIdentifier)]
        return components.url
    }
}
