import Foundation

/// How far a queued ROM download has got.
///
/// Kept as small as it can be: per file detail lives in `DownloadJobFile`, and
/// a job that came through is removed from the queue rather than parked in a
/// finished state.
nonisolated enum DownloadJobState: String, Codable, Equatable {
    /// Persisted, no transfer created for it yet.
    case queued
    /// At least one of its files is being transferred.
    case running
    /// Every file is on disk, the ROM metadata is being written.
    case finalizing
    /// Cancellation was asked for, the transfers may still be winding down.
    case cancelling
    /// The job stopped short and will not carry on by itself.
    case failed
}

nonisolated enum DownloadJobFileState: String, Codable, Equatable {
    case pending
    case running
    case downloaded
    case failed
}

/// One ROM download, persisted so it outlives suspension and app restart.
///
/// A background URLSession keeps transferring while the app is gone, so the
/// state of a download cannot live on a call stack. Everything needed to carry
/// a download on, or to clean up after it, is in here.
nonisolated struct DownloadJob: Codable, Equatable, Identifiable {
    /// Stable across restarts, and the half of `DownloadTaskKey` that points a
    /// session task back at its job.
    let id: UUID
    let romId: Int
    /// As much of the ROM as the queue entry and the ROM metadata need, `Rom`
    /// itself is not `Codable`.
    let rom: DownloadJobRomSnapshot
    /// The resolved platform name. Callers derive it from the ROM's platform or
    /// its slug, and the same value has to be used again after a restart, so it
    /// is stored rather than worked out twice.
    let platformName: String
    /// Target directory relative to the ROM library root. Relative because the
    /// app container path is not stable across launches.
    ///
    /// Set from `LocalROMRepository.createROMDirectoryPath` when the job is
    /// queued, because the job is persisted before anything is prepared, and
    /// overwritten with the path the download finalizer actually prepared. The
    /// finalizer has the last word: a transfer must not write anywhere it will
    /// not look afterwards.
    var romDirectoryPath: String
    let createdAt: Date
    var state: DownloadJobState
    var files: [DownloadJobFile]
    /// How often this job was restarted automatically after an interruption, so
    /// a download that cannot get through stops instead of looping.
    var restartCount: Int
    /// Why the job stopped, in the words the queue shows the user. Only carries
    /// a value alongside `failed`. Optional so a queue file written before this
    /// field existed still decodes.
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        romId: Int,
        rom: DownloadJobRomSnapshot,
        platformName: String,
        romDirectoryPath: String,
        createdAt: Date = Date(),
        state: DownloadJobState = .queued,
        files: [DownloadJobFile],
        restartCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.romId = romId
        self.rom = rom
        self.platformName = platformName
        self.romDirectoryPath = romDirectoryPath
        self.createdAt = createdAt
        self.state = state
        self.files = files
        self.restartCount = restartCount
        self.errorMessage = errorMessage
    }
}

/// One file of a ROM download.
nonisolated struct DownloadJobFile: Codable, Equatable, Identifiable {
    /// File names are unique inside a ROM directory, so the name is also the
    /// key a transfer is matched by.
    var id: String { fileName }

    let fileName: String
    /// Size taken from the server metadata. The server can build archives while
    /// it serves them, so the transferred byte count may differ from this. It
    /// is a hint for display and for the storage check, never a criterion for
    /// calling a file complete.
    let expectedSizeBytes: Int64
    /// Set once this file switched to `api/roms/{id}/content` because the per
    /// file path answered 404, so a restart does not have to learn that again.
    var usesLegacyContentPath: Bool
    var state: DownloadJobFileState
    /// Bytes written as last reported by URLSession, kept so progress stays
    /// continuous across an interruption. Not a statement about the file on
    /// disk, only the last checkpoint that was seen.
    var receivedBytes: Int64

    init(
        fileName: String,
        expectedSizeBytes: Int64,
        usesLegacyContentPath: Bool = false,
        state: DownloadJobFileState = .pending,
        receivedBytes: Int64 = 0
    ) {
        self.fileName = fileName
        self.expectedSizeBytes = expectedSizeBytes
        self.usesLegacyContentPath = usesLegacyContentPath
        self.state = state
        self.receivedBytes = receivedBytes
    }
}

/// The part of a `Rom` a download job carries along.
///
/// Same idea as `DownloadedROM`: enough to show the entry and to write the ROM
/// metadata afterwards, not a full server ROM. A `Rom` rebuilt from a snapshot
/// therefore has the defaults of everything that was not worth persisting.
nonisolated struct DownloadJobRomSnapshot: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let platformId: Int
    let platformSlug: String?
    let urlCover: String?
    let fileName: String?
    let sizeBytes: Int?

    init(
        id: Int,
        name: String,
        platformId: Int,
        platformSlug: String? = nil,
        urlCover: String? = nil,
        fileName: String? = nil,
        sizeBytes: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.platformId = platformId
        self.platformSlug = platformSlug
        self.urlCover = urlCover
        self.fileName = fileName
        self.sizeBytes = sizeBytes
    }

    /// `Rom` is main actor bound, so building a snapshot from one and rebuilding
    /// one from a snapshot both stay on the main actor. The stored fields are
    /// readable from anywhere.
    @MainActor
    init(rom: Rom) {
        self.init(
            id: rom.id,
            name: rom.name,
            platformId: rom.platformId,
            platformSlug: rom.platformSlug,
            urlCover: rom.urlCover,
            fileName: rom.fileName,
            sizeBytes: rom.sizeBytes
        )
    }

    @MainActor
    func toRom() -> Rom {
        Rom(
            id: id,
            name: name,
            platformId: platformId,
            urlCover: urlCover,
            sizeBytes: sizeBytes,
            fileName: fileName,
            platformSlug: platformSlug
        )
    }
}
