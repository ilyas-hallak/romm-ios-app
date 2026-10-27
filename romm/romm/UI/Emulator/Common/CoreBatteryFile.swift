import Foundation

/// A running game's battery save exists twice: the store's copy, which outlives
/// the session and syncs with the server, and the file the core reads when it
/// starts and writes whenever it pauses. This keeps the two in step.
///
/// The core's file can be ahead of the store: a session that ends without a
/// clean quit (swiped away, crashed, killed in the background) has already
/// written it, but never got to copy it back. Copying the store over it on the
/// next start would throw that progress away (issue #189).
struct CoreBatteryFile {
    let url: URL
    let romId: Int
    let saveStates: PEmulatorSaveStatesUseCase

    enum StageOutcome: Equatable {
        case nothingStored
        case staged
        /// The core's file was newer and went into the store instead, so it
        /// still has to reach the server.
        case adoptedCoreFile(Data)
    }

    struct Collected {
        let data: Data
        let isNew: Bool
    }

    /// Hands the stored save to the core before it starts. `adapt` turns the
    /// stored bytes into the layout this core expects.
    func stage(adapt: (Data) -> Data = { $0 }) -> StageOutcome {
        guard let stored = try? saveStates.readBattery(romId: romId) else { return .nothingStored }
        let forCore = adapt(stored)
        let coreData = try? Data(contentsOf: url)
        if coreData == forCore { return .staged }
        if let coreData, isCoreFileNewer {
            try? saveStates.writeBattery(romId: romId, data: coreData)
            return .adoptedCoreFile(coreData)
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? forCore.write(to: url, options: .atomic)
        return .staged
    }

    /// Copies what the core last wrote into the store, or returns `nil` when
    /// the core has not written anything yet.
    func collect() -> Collected? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let isNew = (try? saveStates.readBattery(romId: romId)) != data
        if isNew {
            try? saveStates.writeBattery(romId: romId, data: data)
        }
        return Collected(data: data, isNew: isNew)
    }

    /// An unknown timestamp on either side keeps the store in charge, as it
    /// always was.
    private var isCoreFileNewer: Bool {
        let coreDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let coreDate, let storeDate = saveStates.batteryModifiedAt(romId: romId) else { return false }
        return coreDate > storeDate
    }
}
