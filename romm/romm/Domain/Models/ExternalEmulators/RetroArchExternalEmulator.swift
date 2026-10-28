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
    /// knows the ROM, which the App Store build does not ship.
    ///
    /// Started by path alone, RetroArch takes the first core that claims the
    /// extension, e.g. a DS core for `gba`. So where the core is known, the
    /// `topshelf` link names it. `~` is RetroArch's home directory, `:` its
    /// app bundle.
    func launchURL(gameIdentifier: String, platformSlug: String) -> URL? {
        guard !gameIdentifier.isEmpty else { return nil }
        let romPath = "~/Documents/RetroArch/downloads/\(gameIdentifier)"
        var components = URLComponents()
        components.scheme = urlScheme
        guard let core = PlatformSlugToGameType.map(platformSlug).map(Self.coreName) else {
            components.host = "game"
            components.path = "/\(romPath)"
            return components.url
        }
        let framework = core.replacingOccurrences(of: "_", with: ".") + ".libretro"
        components.host = "topshelf"
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "path", value: Self.queryEncoded(romPath)),
            URLQueryItem(name: "core_path", value: Self.queryEncoded(":/Frameworks/\(framework).framework/\(framework)"))
        ]
        return components.url
    }

    /// The core RetroArch ships for each system, by the name of its
    /// `<name>_libretro` library.
    static func coreName(for gameType: DeltaGameType) -> String {
        switch gameType {
        case .gba: return "mgba"
        case .snes: return "snes9x"
        case .nes: return "fceumm"
        case .gbc: return "gambatte"
        case .n64: return "mupen64plus_next"
        case .ds: return "melondsds"
        case .genesis: return "genesis_plus_gx"
        }
    }

    /// `URLComponents` leaves `&`, `=` and `+` alone in a query, all of which
    /// show up in ROM file names and would split or alter the value.
    private static func queryEncoded(_ value: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// RetroArch ships under several identifiers (`com.libretro.RetroArch`,
    /// `…RetroArchiOS11`, plus ad-hoc builds), so match on the substring.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().contains("retroarch")
    }
}
