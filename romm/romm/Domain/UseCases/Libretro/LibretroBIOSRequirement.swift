import Foundation

/// Beschreibt eine einzelne BIOS-Datei, die ein libretro-Core benötigt.
struct LibretroBIOSFile: Hashable, Sendable {
    /// Erwarteter Dateiname im `LibretroSystem`-Verzeichnis (case-sensitive).
    let fileName: String
    /// Optionaler kanonischer MD5-Hash zur Verifikation. Lowercase Hex.
    let canonicalMD5: String?
    /// Wenn `true`: Core startet ohne diese Datei nicht. Sonst optional/Regional.
    let required: Bool
    /// Menschenlesbare Beschreibung.
    let note: String?
    /// Unterverzeichnis relativ zum `LibretroSystem`-Verzeichnis. `nil` = flach
    /// direkt in systemDir (PS1, Sega CD). Flycast erwartet seine BIOS-Dateien
    /// dagegen in `<systemDir>/dc/`.
    let subdirectory: String?

    init(
        fileName: String,
        canonicalMD5: String?,
        required: Bool,
        note: String?,
        subdirectory: String? = nil
    ) {
        self.fileName = fileName
        self.canonicalMD5 = canonicalMD5
        self.required = required
        self.note = note
        self.subdirectory = subdirectory
    }
}

extension LibretroBIOSFile {
    /// Erwarteter Ablageort dieser Datei unterhalb von `systemDir`. Einzige
    /// Stelle, an der aus Requirement + systemDir ein Pfad wird, damit Lesen
    /// (Status) und Schreiben (Download) nicht auseinanderlaufen können.
    func localURL(in systemDir: URL) -> URL {
        guard let subdirectory else {
            return systemDir.appendingPathComponent(fileName)
        }
        return systemDir
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

/// BIOS-Anforderungen pro libretro-Core. Quelle: libretro-docs für PCSX ReARMed.
enum LibretroBIOSRequirement {
    static func files(for core: LibretroCore) -> [LibretroBIOSFile] {
        switch core {
        case .pcsxRearmed:
            return [
                LibretroBIOSFile(
                    fileName: "scph5500.bin",
                    canonicalMD5: "8dd7d5296a650fac7319bce665a6a53c",
                    required: false,
                    note: "PS1 BIOS – Japan (SCPH-5500)"
                ),
                LibretroBIOSFile(
                    fileName: "scph5501.bin",
                    canonicalMD5: "490f666e1afb15b7362b406ed1cea246",
                    required: false,
                    note: "PS1 BIOS – USA (SCPH-5501)"
                ),
                LibretroBIOSFile(
                    fileName: "scph5502.bin",
                    canonicalMD5: "32736f17079d0b2b7024407c39bd3050",
                    required: false,
                    note: "PS1 BIOS – Europe (SCPH-5502)"
                )
            ]
        case .beetlePCEFast:
            // HuCard games need no BIOS. (PCE-CD would need syscard3.pce — out of scope for now.)
            return []
        case .genesisPlusGX:
            // Master System / Game Gear / SG-1000 / Genesis carts need no BIOS.
            // Sega CD needs a region BIOS; any one region is enough (see below).
            return [
                LibretroBIOSFile(
                    fileName: "bios_CD_U.bin",
                    canonicalMD5: "2efd74e3232ff260e371b99f84024f7f",
                    required: false,
                    note: "Sega CD BIOS – USA"
                ),
                LibretroBIOSFile(
                    fileName: "bios_CD_E.bin",
                    canonicalMD5: "e66fa1dc5820d254611fdcdba0662372",
                    required: false,
                    note: "Sega CD BIOS – Europe"
                ),
                LibretroBIOSFile(
                    fileName: "bios_CD_J.bin",
                    canonicalMD5: "278a9397d192149e84e820ac621a8edd",
                    required: false,
                    note: "Sega CD BIOS – Japan"
                )
            ]
        case .flycast:
            // Flycast liest beide Dateien aus <systemDir>/dc/, nicht flach.
            return [
                LibretroBIOSFile(
                    fileName: "dc_boot.bin",
                    canonicalMD5: "e10c53c2f8b90bab96ead2d368858623",
                    required: true,
                    note: "Dreamcast Boot ROM",
                    subdirectory: "dc"
                ),
                LibretroBIOSFile(
                    fileName: "dc_flash.bin",
                    canonicalMD5: "0a93f7940c455905bea6e392dfde92a4",
                    required: true,
                    note: "Dreamcast Flash ROM",
                    subdirectory: "dc"
                )
            ]
        case .ppsspp:
            // PSP-Spiele booten ohne BIOS: PPSSPP emuliert die Firmware per HLE.
            // Die Assets (ppge_atlas, flash0/font, vfpu-Tabellen) liefert die App
            // selbst mit, siehe PPSSPPAssetsInstaller.
            return []
        }
    }

    /// Mindestens eine dieser Dateien muss existieren, sonst kein Start.
    /// PCSX ReARMed akzeptiert jede Regionalvariante; mindestens eine reicht.
    static func atLeastOneOfFileNames(for core: LibretroCore) -> [String]? {
        switch core {
        case .pcsxRearmed:
            return ["scph5500.bin", "scph5501.bin", "scph5502.bin"]
        case .beetlePCEFast:
            return nil
        case .genesisPlusGX:
            // No hard gate: SMS/GG/SG-1000/Genesis carts boot without any BIOS.
            // Sega CD BIOS is optional and only needed for CD images.
            return nil
        case .flycast:
            // Kein "eines von mehreren": dc_boot.bin UND dc_flash.bin sind beide
            // required, das deckt `files(for:)` mit required: true bereits ab.
            return nil
        case .ppsspp:
            // Kein BIOS, also auch kein Start-Gate.
            return nil
        }
    }

    /// libretro-Slug-Mapping → ROMM-Plattformen, die zu diesem Core gehören.
    /// Wird in der Settings-UI benutzt, um die Plattform-Firmware-Liste zu
    /// finden, ohne dass alle Plattformen geladen werden müssen.
    static func platformSlugs(for core: LibretroCore) -> [String] {
        switch core {
        case .pcsxRearmed:
            return ["ps", "ps1", "psx", "playstation"]
        case .beetlePCEFast:
            return ["pce", "pc-engine", "turbografx-16", "tg16"]
        case .genesisPlusGX:
            return ["sms", "master-system", "gamegear", "game-gear", "sg1000", "segacd", "sega-cd"]
        case .flycast:
            return ["dc", "dreamcast"]
        case .ppsspp:
            return ["psp", "playstation-portable"]
        }
    }
}
