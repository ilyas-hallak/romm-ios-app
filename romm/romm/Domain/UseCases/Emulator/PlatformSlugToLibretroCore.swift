import Foundation

enum LibretroCore: String, Codable, Sendable {
    case pcsxRearmed = "pcsx_rearmed"
    case beetlePCEFast = "beetle_pce_fast"
    // Zukünftig: case ppsspp, case beetlePsx, ...

    var dylibName: String {
        switch self {
        case .pcsxRearmed: return "pcsx_rearmed_libretro_ios"
        case .beetlePCEFast: return "mednafen_pce_fast_libretro_ios"
        }
    }

    var displayName: String {
        switch self {
        case .pcsxRearmed: return "PlayStation (PCSX ReARMed)"
        case .beetlePCEFast: return "PC Engine / TurboGrafx-16 (Beetle PCE FAST)"
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
        return nil
    }
}
