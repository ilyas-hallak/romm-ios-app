import Foundation

/// RetroArch resolves `retroarch://game/<name.ext>` against its own library, so
/// the plain file name is the identifier and nothing has to be hashed.
///
/// It also opens archives itself, so the handoff can pass a ROM along exactly as
/// it is stored.
struct RetroArchExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .retroarch }
    var displayName: String { "RetroArch" }
    var urlScheme: String { "retroarch" }
    var identifierKind: ExternalGameIdentifierKind { .fileName }
    var wantsUnpackedROM: Bool { false }

    /// Saves sit under `RetroArch/saves/<core>/`, per issue #144. The hint stops
    /// above the core directory, since that level is one entry per core.
    ///
    /// Getting the hint right matters more here than elsewhere: a RetroArch
    /// folder usually holds the user's whole ROM collection too, so falling back
    /// to walking it would mean reading through all of that.
    var saveLayout: ExternalSaveLayout? {
        ExternalSaveLayout(
            naming: .romBaseName,
            batteryExtensions: ["srm", "sav"],
            searchHints: ["RetroArch/saves", "saves"]
        )
    }

    /// RetroArch ships under several identifiers (`com.libretro.RetroArch`,
    /// `…RetroArchiOS11`, plus ad-hoc builds), so match on the substring.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().contains("retroarch")
    }
}
