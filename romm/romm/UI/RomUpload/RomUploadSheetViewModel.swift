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
        factory: PDependencyFactory = DefaultDependencyFactory.shared,
        queueManager: RomUploadQueueManager = .shared
    ) {
        self.file = file
        self.getPlatformsUseCase = factory.makeGetPlatformsUseCase()
        self.getAvailabilityUseCase = factory.makeGetRomUploadAvailabilityUseCase()
        self.suggestPlatformUseCase = factory.makeSuggestPlatformForFileUseCase()
        self.discardStagedRomUseCase = factory.makeDiscardStagedRomUseCase()
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
            return "This sign-in does not include permission to upload ROMs. Sign out and sign in again to allow uploads."
        case .notAllowedForAccount:
            return "Your account is not allowed to upload ROMs. Ask a server admin for a role that can."
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
