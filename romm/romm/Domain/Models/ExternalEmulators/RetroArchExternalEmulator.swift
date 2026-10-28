import Foundation

/// RetroArch is identified by the plain file name, so nothing has to be hashed.
///
/// It gets the unpacked ROM wherever the built-in engines know the platform:
/// started by path, RetroArch takes the first core that claims the extension,
/// and for `zip` that is an Amiga or Amstrad core.
struct RetroArchExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .retroarch }
    var displayName: String { "RetroArch" }
    var urlScheme: String { "retroarch" }
    var appStoreURL: URL? { URL(string: "https://apps.apple.com/app/id6499539433") }
    var identifierKind: ExternalGameIdentifierKind { .fileName }
    var wantsUnpackedROM: Bool { true }

    /// Saves sit under `RetroArch/saves/<core>/`, so the hint stops above the
    /// per-core level. It matters more here than elsewhere, because a RetroArch
    /// folder usually holds the whole ROM collection the fallback would walk.
    var saveLayout: ExternalSaveLayout? {
        ExternalSaveLayout(
            naming: .romBaseName,
            batteryExtensions: ["srm", "sav"],
            searchHints: ["RetroArch/saves", "saves"]
        )
    }

    /// Points the deep link at the file the import copied into RetroArch's
    /// downloads folder. A bare name only resolves against its playlists, and
    /// the import only lands there when RetroArch has a content database that
    /// knows the ROM, which the App Store build does not ship. `~` is expanded
    /// to RetroArch's home directory.
    func launchURL(gameIdentifier: String) -> URL? {
        guard !gameIdentifier.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "game"
        components.path = "/~/Documents/RetroArch/downloads/\(gameIdentifier)"
        return components.url
    }

    /// RetroArch ships under several identifiers (`com.libretro.RetroArch`,
    /// `…RetroArchiOS11`, plus ad-hoc builds), so match on the substring.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().contains("retroarch")
    }
}
