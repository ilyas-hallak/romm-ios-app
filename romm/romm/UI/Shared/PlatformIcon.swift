//
//  PlatformIcon.swift
//  romm
//

import UIKit

/// Resolves a platform's icon asset name from the server-provided slug.
///
/// The slug is a freely chosen folder name on the RomM server, not a stable identifier, and the
/// asset catalog mixes Libretro and IGDB naming conventions. That means a slug and its matching
/// asset frequently disagree (`pcengine` vs. `pce`, `neogeo` vs. `neogeoaes`, `mame2003` vs.
/// `arcade`), and some slugs have no asset at all. `Image(platform.slug)` used directly would
/// silently render nothing in that case, so this type looks the slug up against a small alias
/// table and falls back to a generic placeholder instead.
enum PlatformIcon {
    /// Slugs whose matching asset is named differently, taken from the slug spellings the app's
    /// emulator mappings already expect.
    private static let aliases: [String: String] = [
        "pcengine": "pce",
        "pc-engine": "pce",
        "turbografx": "tg16",
        "turbografx-16": "tg16",
        "turbografx16": "tg16",
        "tg-16": "tg16",
        "turbografx-16-slash-pc-engine": "tg16",
        "pc-engine-cd": "pcecd",
        "pce-cd": "pcecd",
        "sgx": "supergrafx",
        "neogeo": "neogeoaes",
        "neo-geo": "neogeoaes",
        "mame": "arcade",
        "mame2003": "arcade",
        "mame2010": "arcade",
        "mame2015": "arcade",
        "ps": "psx",
        "ps1": "psx",
        "playstation": "psx",
        "sony-playstation": "psx",
        "playstation-portable": "psp",
        "sony-psp": "psp",
        "genesis-slash-megadrive": "genesis",
        "sega-genesis": "genesis",
        "megadrive": "md",
        "mega-drive": "md",
        "smd": "md",
        "dreamcast": "dc",
        "segadc": "dc",
        "master-system": "sms",
        "mastersystem": "sms",
        "sega-master-system": "sms",
        "mark-iii": "sms",
        "game-gear": "gamegear",
        "gg": "gamegear",
        "sega-cd": "segacd",
        "mega-cd": "segacd",
        "megacd": "segacd",
        "nintendo-64": "n64",
        "game-boy": "gb",
        "gameboy": "gb",
        "nintendo-ds": "nds",
        "ds": "nds",
        "dsi": "nintendo-dsi",
        "super-nes": "snes",
        "super-nintendo": "snes",
        "ps4--1": "ps4",
    ]

    /// The generic placeholder asset, used whenever no better candidate exists in the catalog.
    private static let placeholder = "default"

    /// Resolved asset names by slug, so repeated lookups for the same slug (for example while
    /// scrolling a platform list) don't re-run `UIImage(named:)` for every cell.
    @MainActor private static var resolvedCache: [String: String] = [:]

    /// Asset names to try for a server slug, most specific first, ending in the placeholder.
    ///
    /// Pure and deterministic: no asset catalog lookup happens here, which keeps it testable
    /// without a UIKit/SwiftUI environment.
    static func assetNameCandidates(for slug: String?) -> [String] {
        let normalized = slug?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalized, !normalized.isEmpty else { return [placeholder] }

        var candidates = [normalized]

        if let alias = aliases[normalized] {
            candidates.append(alias)
        }

        let collapsed = normalized.filter { $0 != "-" && $0 != "_" }
        if !collapsed.isEmpty {
            candidates.append(collapsed)
        }

        candidates.append(placeholder)

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    /// The first candidate that the asset catalog actually holds, `"default"` if none of them do.
    @MainActor static func assetName(for slug: String?) -> String {
        let cacheKey = slug?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if let cached = resolvedCache[cacheKey] {
            return cached
        }

        let resolved = assetNameCandidates(for: slug).first { UIImage(named: $0) != nil } ?? placeholder
        resolvedCache[cacheKey] = resolved
        return resolved
    }
}
