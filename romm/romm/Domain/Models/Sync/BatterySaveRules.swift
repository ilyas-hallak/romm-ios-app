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

    /// Nil (no local file yet) counts as blank too, matching every call site
    /// that treats "missing" and "blank" the same way.
    static func isBlank(orMissing data: Data?) -> Bool {
        data.map(isBlank) ?? true
    }
}

/// Whether this ROM's local battery file is missing, unreadable, or blank:
/// nothing worth keeping. Shared so every download site reads the file and
/// checks it the same way instead of three slightly different copies.
enum BatteryLocalBattery {
    static func isBlankOrMissing(in saveStore: PSaveStore, romId: Int) -> Bool {
        let data = (try? saveStore.readBattery(romId: romId)).flatMap { $0 }
        return BatterySaveBlank.isBlank(orMissing: data)
    }
}

/// Trims the 16-byte real-time-clock footer some tools (mGBA) append to a GBA
/// battery save. The GBA core only accepts an exact size (VBA-M's
/// `CPUReadBatteryFile`) and silently ignores anything else, so a footer left
/// in place reads back as an empty save.
///
/// Gated on the platform: some of the valid sizes below collide with another
/// platform's own save size plus 16 bytes (an 8192-byte SNES save matches
/// 0x2000 + 16), so trimming by size alone would corrupt a real save on those
/// platforms. A `nil` or unrecognized slug never trims.
enum GBABatteryFooter {
    static let validSizes: Set<Int> = [512, 0x2000, 0x8000, 0x10000, 0x20000]
    static let footerSize = 16

    static func trimmingRTCFooter(from data: Data, platformSlug: String?) -> Data {
        guard let platformSlug, PlatformSlugToGameType.map(platformSlug) == .gba else { return data }
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

    /// The second gate, after `shouldApply` said to go ahead and the bytes are
    /// actually in hand: a candidate that turns out to be blank (a web upload
    /// saved before the game was ever played, or any other foreign-slot row
    /// with nothing in it) must never overwrite a local battery that has a
    /// real save in it. `shouldApply` only knows timestamps, so this is
    /// checked again once the downloaded data itself is known.
    static func mayReplaceLocal(downloaded: Data, localIsBlank: Bool) -> Bool {
        localIsBlank || !BatterySaveBlank.isBlank(downloaded)
    }
}
