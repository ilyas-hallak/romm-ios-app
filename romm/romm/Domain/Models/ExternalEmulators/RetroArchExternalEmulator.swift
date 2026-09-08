import Foundation

/// RetroArch resolves `retroarch://game/<name.ext>` against its own library, so
/// the plain file name is the identifier and nothing has to be hashed.
///
/// It opens archives itself, so a ROM can be passed exactly as it is stored.
struct RetroArchExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .retroarch }
    var displayName: String { "RetroArch" }
    var urlScheme: String { "retroarch" }
    var appStoreURL: URL? { URL(string: "https://apps.apple.com/app/id6499539433") }
    var identifierKind: ExternalGameIdentifierKind { .fileName }
    var wantsUnpackedROM: Bool { false }

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

    /// RetroArch ships under several identifiers (`com.libretro.RetroArch`,
    /// `…RetroArchiOS11`, plus ad-hoc builds), so match on the substring.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().contains("retroarch")
    }
}
