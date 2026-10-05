import Foundation

/// Pure rules shared by every battery sync path (the pre-launch pull, the
/// end-of-session push, and the manual sync preview/runner), so the two never
/// grow different ideas of "blank", "newer", or "the right bytes to write".
/// See issue #208.

/// A cartridge battery that was never actually written to: every byte is
/// 0xFF (a freshly formatted/never-saved image) or every byte is 0x00. Such a
/// file must never be uploaded (it would overwrite a real save with nothing)
/// and must never block a download (a blank local file is as good as absent).
enum BatterySaveBlank {
    static func isBlank(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        return data.allSatisfy { $0 == 0xFF } || data.allSatisfy { $0 == 0x00 }
    }
}

/// Trims the 16-byte real-time-clock footer some tools (mGBA) append to a GBA
/// battery save. The GBA core only accepts an exact size (VBA-M's
/// `CPUReadBatteryFile`) and silently ignores anything else, so a footer left
/// in place reads back as an empty save.
///
/// Sized rather than platform-gated: the call sites that write a downloaded
/// battery (`CloudSaveSyncService`, `SaveSyncRunner`) only know the ROM id and
/// the emulator tag, not the platform, and none of the valid sizes below plus
/// 16 collides with another platform's save size, so this never misfires.
enum GBABatteryFooter {
    static let validSizes: Set<Int> = [512, 0x2000, 0x8000, 0x10000, 0x20000]
    static let footerSize = 16

    static func trimmingRTCFooter(from data: Data) -> Data {
        guard validSizes.contains(data.count - footerSize) else { return data }
        return data.prefix(data.count - footerSize)
    }
}

/// Picks the newest of several candidate rows a sync source has to choose
/// from (negotiate operations, or server save rows), by `updatedAt`. A
/// candidate without a timestamp never wins over one that has one.
enum BatteryDownloadPicker {
    static func pickNewest<T>(_ candidates: [T], updatedAt: (T) -> Date?) -> T? {
        candidates.max { (updatedAt($0) ?? .distantPast) < (updatedAt($1) ?? .distantPast) }
    }
}

/// Whether a candidate server save should replace the local battery: either
/// it is genuinely newer, or the local file has nothing worth keeping
/// (missing or blank) regardless of timestamps.
enum BatteryDownloadDecision {
    static func shouldApply(candidateUpdatedAt: Date?, localModifiedAt: Date?, localIsBlank: Bool) -> Bool {
        guard let localModifiedAt, !localIsBlank else { return true }
        guard let candidateUpdatedAt else { return false }
        return candidateUpdatedAt > localModifiedAt
    }
}
