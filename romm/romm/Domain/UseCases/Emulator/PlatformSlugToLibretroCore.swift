import Foundation

enum LibretroCore: String, Codable, Sendable {
    case pcsxRearmed = "pcsx_rearmed"
    case beetlePCEFast = "beetle_pce_fast"
    case genesisPlusGX = "genesis_plus_gx"
    // Zukünftig: case ppsspp, case beetlePsx, ...

    var dylibName: String {
        switch self {
        case .pcsxRearmed: return "pcsx_rearmed_libretro_ios"
        case .beetlePCEFast: return "mednafen_pce_fast_libretro_ios"
        case .genesisPlusGX: return "genesis_plus_gx_libretro_ios"
        }
    }

    var displayName: String {
        switch self {
        case .pcsxRearmed: return "PlayStation (PCSX ReARMed)"
        case .beetlePCEFast: return "PC Engine / TurboGrafx-16 (Beetle PCE FAST)"
        case .genesisPlusGX: return "Sega Master System / Game Gear / CD (Genesis Plus GX)"
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .pcsxRearmed:
            return ["bin", "cue", "iso", "img", "mdf", "pbp", "chd", "ecm", "m3u", "toc"]
        case .beetlePCEFast:
            // HuCard (.pce/.sgx) plus CD image formats (SuperGrafx via .sgx).
            // NOTE: never list "zip"/"7z" here — the resolver must EXTRACT archives
            // and hand the inner ROM to the core, not the archive itself.
            return ["pce", "sgx", "cue", "ccd", "chd", "iso", "img", "bin", "m3u", "toc"]
        case .genesisPlusGX:
            // Master System (.sms), Game Gear (.gg), SG-1000 (.sg), Genesis/MD carts
            // (.md/.gen/.smd/.bin) and Sega CD images (.cue/.iso/.chd). No archives.
            return ["sms", "gg", "sg", "md", "gen", "smd", "mdx", "bin",
                    "cue", "iso", "chd", "m3u", "toc"]
        }
    }
}

enum PlatformSlugToLibretroCore {
    static func map(_ slug: String) -> LibretroCore? {
        let s = slug.lowercased()
        if s == "ps" || s == "ps1" || s == "psx" || s == "playstation"
            || s.contains("playstation 1") || s.contains("playstation-1")
            || s == "sony-playstation" {
            return .pcsxRearmed
        }
        if s == "pce" || s == "pc-engine" || s == "pcengine"
            || s == "tg16" || s == "tg-16" || s == "turbografx16" || s == "turbografx-16"
            || s == "pce-cd" || s == "pc-engine-cd" || s == "turbografx-cd"
            || s == "sgx" || s == "supergrafx"
            || s.contains("turbografx") || s.contains("pc engine") || s.contains("pc-engine") {
            return .beetlePCEFast
        }
        // Genesis Plus GX only serves the Sega systems Delta does NOT cover.
        // Genesis/Mega Drive stay on DeltaCore (PlatformSlugToGameType wins first
        // in LaunchEmulatorUseCase), so they are intentionally NOT mapped here.
        if s == "sms" || s == "master-system" || s == "sega-master-system"
            || s == "mark-iii" || s.contains("master system")
            || s == "gamegear" || s == "game-gear" || s == "gg" || s.contains("game gear")
            || s == "sg1000" || s == "sg-1000" || s.contains("sg-1000")
            || s == "segacd" || s == "sega-cd" || s == "mega-cd" || s == "megacd"
            || s == "sega-cd-32x" || s.contains("sega cd") || s.contains("mega cd") {
            return .genesisPlusGX
        }
        return nil
    }
}
