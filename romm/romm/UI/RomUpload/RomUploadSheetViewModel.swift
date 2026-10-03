//
//  RomUploadSheetViewModel.swift
//  romm
//

import Foundation
import Observation

@Observable
@MainActor
final class RomUploadSheetViewModel {
    let file: StagedRomFile

    private(set) var platforms: [Platform] = []
    var selectedPlatformId: Int?
    private(set) var availability: RomUploadAvailability = .unknown
    private(set) var isLoading = true
    /// Set once `upload()` enqueues the job, so the sheet can dismiss itself.
    private(set) var didEnqueue = false

    private let getPlatformsUseCase: GetPlatformsUseCase
    private let getAvailabilityUseCase: GetRomUploadAvailabilityUseCase
    private let suggestPlatformUseCase: SuggestPlatformForFileUseCase
    private let discardStagedRomUseCase: DiscardStagedRomUseCase
    private let queueManager: RomUploadQueueManager

    init(
        file: StagedRomFile,
        getPlatformsUseCase: GetPlatformsUseCase,
        getAvailabilityUseCase: GetRomUploadAvailabilityUseCase,
        suggestPlatformUseCase: SuggestPlatformForFileUseCase,
        discardStagedRomUseCase: DiscardStagedRomUseCase,
        queueManager: RomUploadQueueManager = .shared
    ) {
        self.file = file
        self.getPlatformsUseCase = getPlatformsUseCase
        self.getAvailabilityUseCase = getAvailabilityUseCase
        self.suggestPlatformUseCase = suggestPlatformUseCase
        self.discardStagedRomUseCase = discardStagedRomUseCase
        self.queueManager = queueManager
    }

    var canUpload: Bool {
        guard case .available = availability else { return false }
        return selectedPlatformId != nil
    }

    /// Copy for the banner shown when upload is not possible, nil when it is.
    var unavailableMessage: String? {
        switch availability {
        case .available:
            return nil
        case .missingScope:
            return "This device is not authorized to upload ROMs. Pair it again to pick up the upload permission."
        case .serverTooOld(let version):
            return "Uploading needs RomM 4.8.0 or newer. This server is on \(version)."
        case .unknown:
            return "Could not reach the server to check whether uploads are supported."
        }
    }

    func load() async {
        isLoading = true
        async let availabilityResult = getAvailabilityUseCase.execute()
        async let platformsResult = (try? getPlatformsUseCase.execute()) ?? []
        availability = await availabilityResult
        platforms = await platformsResult.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedPlatformId = suggestPlatformUseCase.execute(fileName: file.fileName, platforms: platforms)?.id
        isLoading = false
    }

    func upload() {
        guard let platformId = selectedPlatformId,
              let platform = platforms.first(where: { $0.id == platformId }) else { return }
        queueManager.enqueue(file: file, platformId: platformId, platformName: platform.name)
        didEnqueue = true
    }

    /// Called when the sheet is dismissed without an upload, so the staged
    /// copy does not linger.
    func discardIfNotUploaded() {
        guard !didEnqueue else { return }
        discardStagedRomUseCase.execute(file)
    }
}

extension RomUploadSheetViewModel {
    /// Builds a view model wired to the app's real dependencies, so call
    /// sites (`AppView`) do not have to know what it needs.
    static func make(file: StagedRomFile) -> RomUploadSheetViewModel {
        RomUploadSheetViewModel(
            file: file,
            getPlatformsUseCase: DefaultDependencyFactory.shared.makeGetPlatformsUseCase(),
            getAvailabilityUseCase: DefaultDependencyFactory.shared.makeGetRomUploadAvailabilityUseCase(),
            suggestPlatformUseCase: DefaultDependencyFactory.shared.makeSuggestPlatformForFileUseCase(),
            discardStagedRomUseCase: DefaultDependencyFactory.shared.makeDiscardStagedRomUseCase()
        )
    }
}
