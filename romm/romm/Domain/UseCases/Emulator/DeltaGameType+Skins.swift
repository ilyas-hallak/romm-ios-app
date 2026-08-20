import Foundation

extension DeltaGameType {
    /// The identifier Delta uses for this system, both in `Delta.registeredCores`
    /// and in a controller skin's `info.json`. The raw values line up exactly, so
    /// every case maps without a lookup table.
    var gameTypeIdentifier: String { "com.rileytestut.delta.game.\(rawValue)" }

    init?(gameTypeIdentifier: String) {
        let prefix = "com.rileytestut.delta.game."
        guard gameTypeIdentifier.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(gameTypeIdentifier.dropFirst(prefix.count)))
    }

    var displayName: String {
        switch self {
        case .gba: return "Game Boy Advance"
        case .gbc: return "Game Boy / Color"
        case .nes: return "NES"
        case .snes: return "Super Nintendo"
        case .n64: return "Nintendo 64"
        case .ds: return "Nintendo DS"
        case .genesis: return "Sega Genesis"
        }
    }
}
