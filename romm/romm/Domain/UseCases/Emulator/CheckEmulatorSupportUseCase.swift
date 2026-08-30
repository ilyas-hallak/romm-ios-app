//
//  CheckEmulatorSupportUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 21.12.24.
//

import Foundation

/// Use case to check if a platform is supported for emulation
protocol PCheckEmulatorSupportUseCase {
    func execute(platformSlug: String) -> Bool
}

class CheckEmulatorSupportUseCase: PCheckEmulatorSupportUseCase {

    // Supported platforms based on what EmulatorJS provides
    // This maps platform slugs/names to whether they are supported
    private let supportedPlatforms: Set<String> = [
        // Nintendo
        "nes", "nintendo entertainment system",
        "snes", "super nintendo", "super nintendo entertainment system",
        "n64", "nintendo 64",
        "gba", "game boy advance",
        "gbc", "game boy color",
        "gb", "game boy",
        "nds", "nintendo ds",

        // Sega
        "genesis", "mega drive", "sega genesis", "sega mega drive",
        "master system", "sega master system", "sms", "mark-iii",
        "game gear", "sega game gear", "gamegear",
        "sg1000", "sg-1000",
        "segacd", "sega cd", "mega-cd", "megacd",
        "saturn", "sega saturn",
        // Dreamcast ("dc") ist bewusst deaktiviert: Flycast laeuft zwar inkl.
        // HW-Rendering, die Audioausgabe ist aber zeitweise zu schnell. Zum
        // Freischalten hier und in PlatformROMsListView.isPlatformSupported "dc"
        // ergaenzen.
        "dreamcast", "sega dreamcast",

        // Sony
        "psx", "ps1", "playstation", "playstation 1",
        "psp", "playstation portable",

        // NEC
        "pc engine", "pc-engine", "pce", "turbografx", "tg16", "supergrafx",

        // Other
        "arcade"
    ]

    /// Check if a platform is supported for emulation
    /// - Parameter platformSlug: The platform slug or display name (case-insensitive)
    /// - Returns: True if the platform is supported, false otherwise
    func execute(platformSlug: String) -> Bool {
        let normalizedSlug = platformSlug.lowercased()

        // Check if any supported platform matches
        return supportedPlatforms.contains { supportedPlatform in
            normalizedSlug.contains(supportedPlatform)
        }
    }
}
