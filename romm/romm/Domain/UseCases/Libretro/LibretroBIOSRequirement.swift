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
        }
    }
}
