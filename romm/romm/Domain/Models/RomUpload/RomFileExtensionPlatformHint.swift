//
//  RomFileExtensionPlatformHint.swift
//  romm
//

import Foundation

/// Maps a file extension to the platform slugs it is likely to belong to, so
/// the upload sheet can preselect a platform instead of leaving an empty
/// picker. Archives and disc images are ambiguous on their own and get no
/// candidates.
enum RomFileExtensionPlatformHint {
    private static let candidatesByExtension: [String: [String]] = [
        "gba": ["gba"],
        "gb": ["gb"],
        "gbc": ["gbc"],
        "nes": ["nes"],
        "sfc": ["snes"],
        "smc": ["snes"],
        "n64": ["n64"],
        "z64": ["n64"],
        "v64": ["n64"],
        "nds": ["nds"],
        "md": ["genesis-slash-megadrive", "genesis", "megadrive"],
        "gen": ["genesis-slash-megadrive", "genesis", "megadrive"],
        "smd": ["genesis-slash-megadrive", "genesis", "megadrive"],
        "cue": ["ps", "psx"],
        "chd": ["ps", "psx"],
        "pbp": ["ps", "psx"],
        "cso": ["psp"],
    ]

    /// Candidate platform slugs for `fileName`'s extension, lowercased. Empty
    /// when the extension is unknown or inherently ambiguous (zip, 7z, iso).
    static func candidateSlugs(forFileName fileName: String) -> [String] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return candidatesByExtension[ext] ?? []
    }
}
