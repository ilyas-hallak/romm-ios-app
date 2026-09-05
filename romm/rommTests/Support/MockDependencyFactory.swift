//
//  MockDependencyFactory.swift
//  rommTests
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation
@testable import romm

// MARK: - Mock Factory for Testing

/// Test double for `PDependencyFactory`. Every dependency must be injected
/// explicitly; anything left unset traps with `fatalError` on first access
/// instead of falling back to a real implementation. This guarantees a test
/// that forgets a dependency fails loudly rather than silently hitting the
/// network, the keychain or the disk.
///
/// Dependencies that only talk to the server go through the injected
/// `apiClient` (defaulting to `FakeAPIClient()`), so they can be built for
/// real without any risk of a real request escaping.
class MockDependencyFactory: PDependencyFactory {
    // Repositories that only reach the server via `apiClient` are built for
    // real against the (fake) client, so no request ever leaves the process.
    var authRepository: PAuthRepository
    var romsRepository: PRomsRepository
    var platformsRepository: PPlatformsRepository
    var collectionsRepository: PCollectionsRepository
    var statsRepository: PStatsRepository
    var heartbeatRepository: PHeartbeatRepository
    var apiClient: PRommAPIClient

    // Side-effecting dependencies (disk, keychain, Core Data). These trap on
    // access unless a test injects a double, via the `_injected…` backing
    // stores below.
    private let _injectedTransferHistoryRepository: PTransferHistoryRepository?
    var transferHistoryRepository: PTransferHistoryRepository {
        _injectedTransferHistoryRepository ?? { fatalError("PTransferHistoryRepository was not stubbed") }()
    }

    private let _injectedLocalROMRepository: PLocalROMRepository?
    var localROMRepository: PLocalROMRepository {
        _injectedLocalROMRepository ?? { fatalError("PLocalROMRepository was not stubbed") }()
    }

    private let _injectedSetupRepository: PSetupRepository?
    var setupRepository: PSetupRepository {
        _injectedSetupRepository ?? { fatalError("PSetupRepository was not stubbed") }()
    }

    private let _injectedSFTPRepository: PSFTPRepository?
    var sftpRepository: PSFTPRepository {
        _injectedSFTPRepository ?? { fatalError("PSFTPRepository was not stubbed") }()
    }

    private let _injectedFileSystemRepository: PFileSystemRepository?
    var fileSystemRepository: PFileSystemRepository {
        _injectedFileSystemRepository ?? { fatalError("PFileSystemRepository was not stubbed") }()
    }

    private let _injectedSFTPKeychainService: PSFTPKeychainService?
    var sftpKeychainService: PSFTPKeychainService {
        _injectedSFTPKeychainService ?? { fatalError("PSFTPKeychainService was not stubbed") }()
    }

    private let _injectedSFTPService: PSFTPService?
    var sftpService: PSFTPService {
        _injectedSFTPService ?? { fatalError("PSFTPService was not stubbed") }()
    }

    // `SFTPConnectionManager` has a private init, so no fresh instance can be
    // created. Without injection the access traps rather than mutating the
    // production `.shared` singleton (which would leak across parallel tests).
    private let _injectedSFTPConnectionManager: SFTPConnectionManager?
    var sftpConnectionManager: SFTPConnectionManager {
        _injectedSFTPConnectionManager ?? { fatalError("SFTPConnectionManager was not stubbed") }()
    }

    private let _injectedFileValidationService: PFileValidationService?
    var fileValidationService: PFileValidationService {
        _injectedFileValidationService ?? { fatalError("PFileValidationService was not stubbed") }()
    }

    // Emulator engine
    lazy var enginePreference: PEmulatorEnginePreference = UserDefaultsEmulatorEnginePreferenceStore()
    lazy var libretroAspectRatioPreference: PLibretroAspectRatioPreference = InMemoryLibretroAspectRatioPreference()
    lazy var emulatorScreenPositionPreference: PEmulatorScreenPositionPreference = InMemoryEmulatorScreenPositionPreference()
    lazy var emulatorMenuShortcutPreference: PEmulatorMenuShortcutPreference = UserDefaultsEmulatorMenuShortcutPreferenceStore()
    lazy var gamepadFaceButtonPreference: PGamepadFaceButtonPreference = UserDefaultsGamepadFaceButtonPreferenceStore()
    lazy var rumblePreference: PRumblePreference = UserDefaultsRumblePreferenceStore()
    lazy var externalDisplayPreference: PExternalDisplayPreference = InMemoryExternalDisplayPreference()
    lazy var screenBrightness: PScreenBrightness = UIScreenBrightness()

    // External emulator apps
    lazy var playTargetPreference: PPlayTargetPreference = UserDefaultsPlayTargetPreferenceStore()
    lazy var externalEmulatorHandoffStore: PExternalEmulatorHandoffStore = UserDefaultsExternalEmulatorHandoffStore()
    lazy var externalAppLauncher: PExternalAppLauncher = UIExternalAppLauncher()

    // MARK: - Changelog / Update Check

    lazy var appUpdateRepository: PAppUpdateRepository = AppUpdateRepository()
    private lazy var appUpdateStateStore: PAppUpdateStateStore = UserDefaultsAppUpdateStateStore()

    func makeAppUpdateUseCase() -> PAppUpdateUseCase {
        AppUpdateUseCase(repository: appUpdateRepository, stateStore: appUpdateStateStore)
    }

    lazy var appUpdateStore: AppUpdateStore = AppUpdateStore(useCase: makeAppUpdateUseCase())

    // Controller skins
    private lazy var controllerSkinInspector: PControllerSkinInspector = DeltaControllerSkinInspector()
    private lazy var controllerSkinRepository: PControllerSkinRepository = ControllerSkinRepository(inspector: controllerSkinInspector)
    private lazy var controllerSkinDownloader: PControllerSkinDownloader = ControllerSkinDownloadService()
    private lazy var controllerSkinPreference: PControllerSkinPreference = UserDefaultsControllerSkinPreferenceStore()
    private lazy var controllerSkinLinkParser: PControllerSkinLinkParser = HTMLControllerSkinLinkParser()

    func makeControllerSkinsUseCase() -> PControllerSkinsUseCase {
        ControllerSkinsUseCase(
            repository: controllerSkinRepository,
            preference: controllerSkinPreference,
            downloader: controllerSkinDownloader,
            linkParser: controllerSkinLinkParser
        )
    }
    
    init(
        authRepository: PAuthRepository? = nil,
        romsRepository: PRomsRepository? = nil,
        platformsRepository: PPlatformsRepository? = nil,
        collectionsRepository: PCollectionsRepository? = nil,
        setupRepository: PSetupRepository? = nil,
        sftpRepository: PSFTPRepository? = nil,
        fileSystemRepository: PFileSystemRepository? = nil,
        statsRepository: PStatsRepository? = nil,
        heartbeatRepository: PHeartbeatRepository? = nil,
        sftpKeychainService: PSFTPKeychainService? = nil,
        sftpService: PSFTPService? = nil,
        sftpConnectionManager: SFTPConnectionManager? = nil,
        apiClient: PRommAPIClient? = nil,
        fileValidationService: PFileValidationService? = nil,
        transferHistoryRepository: PTransferHistoryRepository? = nil,
        localROMRepository: PLocalROMRepository? = nil
    ) {
        // Resolve the API client first so every server-only repository shares it.
        // Defaults to a harmless fake, never the production client.
        let resolvedAPIClient = apiClient ?? FakeAPIClient()
        self.apiClient = resolvedAPIClient

        // Server-only repositories: real implementations are safe because they
        // can only reach the (fake) client, so use the injected double or build
        // one against the fake client.
        self.authRepository = authRepository ?? AuthRepository(apiClient: resolvedAPIClient)
        self.romsRepository = romsRepository ?? RomsRepository(apiClient: resolvedAPIClient)
        self.platformsRepository = platformsRepository ?? PlatformsRepository(apiClient: resolvedAPIClient)
        self.collectionsRepository = collectionsRepository ?? CollectionsRepository(apiClient: resolvedAPIClient)
        self.statsRepository = statsRepository ?? StatsRepository(apiClient: resolvedAPIClient)
        self.heartbeatRepository = heartbeatRepository ?? HeartbeatRepository(apiClient: resolvedAPIClient)

        // Side-effecting dependencies: kept as injected doubles only. When a
        // test omits one, the corresponding property traps on access instead of
        // touching the keychain, the disk or the shared connection manager.
        _injectedSetupRepository = setupRepository
        _injectedFileSystemRepository = fileSystemRepository
        _injectedSFTPKeychainService = sftpKeychainService
        _injectedSFTPRepository = sftpRepository
        _injectedFileValidationService = fileValidationService
        _injectedSFTPService = sftpService
        _injectedSFTPConnectionManager = sftpConnectionManager
        _injectedTransferHistoryRepository = transferHistoryRepository
        _injectedLocalROMRepository = localROMRepository
    }
    
    func makeLogoutUseCase() -> LogoutUseCase {
        LogoutUseCase(authRepository: authRepository)
    }
    
    func makeGetCurrentUserUseCase() -> GetCurrentUserUseCase {
        GetCurrentUserUseCase(authRepository: authRepository)
    }

    func makeRefreshRetroAchievementsUseCase() -> RefreshRetroAchievementsUseCase {
        RefreshRetroAchievementsUseCase(authRepository: authRepository)
    }

    func makeSetRetroAchievementsUsernameUseCase() -> SetRetroAchievementsUsernameUseCase {
        SetRetroAchievementsUsernameUseCase(authRepository: authRepository)
    }
    
    func makeGetRomsUseCase() -> GetRomsUseCase {
        GetRomsUseCase(romsRepository: romsRepository)
    }
    
    func makeGetRomsWithFiltersUseCase() -> GetRomsWithFiltersUseCase {
        GetRomsWithFiltersUseCase(romsRepository: romsRepository)
    }
    
    func makeGetRomDetailsUseCase() -> GetRomDetailsUseCase {
        GetRomDetailsUseCase(romsRepository: romsRepository)
    }
    
    func makeToggleRomFavoriteUseCase() -> ToggleRomFavoriteUseCase {
        ToggleRomFavoriteUseCase(romsRepository: romsRepository)
    }
    
    func makeCheckRomFavoriteStatusUseCase() -> CheckRomFavoriteStatusUseCase {
        CheckRomFavoriteStatusUseCase(romsRepository: romsRepository)
    }

    func makeUpdateLastPlayedUseCase() -> PUpdateLastPlayedUseCase {
        UpdateLastPlayedUseCase(romsRepository: romsRepository)
    }
    
    func makeSearchRomsUseCase() -> SearchRomsUseCase {
        SearchRomsUseCase(romsRepository: romsRepository)
    }
    
    lazy var manualRepository: PManualRepository = ManualRepository(apiClient: apiClient)

    func makeLoadManualUseCase() -> LoadManualUseCase {
        LoadManualUseCase(manualRepository: manualRepository)
    }
    
    func makeGetPlatformsUseCase() -> GetPlatformsUseCase {
        GetPlatformsUseCase(platformsRepository: platformsRepository)
    }
    
    func makeAddPlatformUseCase() -> AddPlatformUseCase {
        AddPlatformUseCase(platformsRepository: platformsRepository)
    }

    func makeGetStatsUseCase() -> GetStatsUseCase {
        GetStatsUseCase(statsRepository: statsRepository)
    }

    func makeGetHeartbeatUseCase() -> GetHeartbeatUseCase {
        GetHeartbeatUseCase(heartbeatRepository: heartbeatRepository)
    }

    func makeCheckServerVersionUseCase() -> CheckServerVersionUseCase {
        CheckServerVersionUseCase(heartbeatRepository: heartbeatRepository)
    }

    func makeClearServerVersionUseCase() -> ClearServerVersionUseCase {
        ClearServerVersionUseCase(heartbeatRepository: heartbeatRepository)
    }

    func makeSaveServerVersionUseCase() -> SaveServerVersionUseCase {
        SaveServerVersionUseCase(heartbeatRepository: heartbeatRepository)
    }

    func makeGetCollectionsUseCase() -> GetCollectionsUseCase {
        GetCollectionsUseCase(collectionsRepository: collectionsRepository)
    }
    
    func makeGetVirtualCollectionsUseCase() -> GetVirtualCollectionsUseCase {
        GetVirtualCollectionsUseCase(collectionsRepository: collectionsRepository)
    }
    
    func makeCreateCollectionUseCase() -> CreateCollectionUseCase {
        CreateCollectionUseCase(collectionsRepository: collectionsRepository)
    }
    
    func makeUpdateCollectionUseCase() -> UpdateCollectionUseCase {
        UpdateCollectionUseCase(collectionsRepository: collectionsRepository)
    }
    
    func makeDeleteCollectionUseCase() -> DeleteCollectionUseCase {
        DeleteCollectionUseCase(collectionsRepository: collectionsRepository)
    }
    
    func makeSaveSetupConfigurationUseCase() -> PSaveSetupConfigurationUseCase {
        SaveSetupConfigurationUseCase(
            setupRepository: setupRepository
        )
    }
    
    func makeGetSetupConfigurationUseCase() -> PGetSetupConfigurationUseCase {
        GetSetupConfigurationUseCase(setupRepository: setupRepository)
    }
    
    func makeCheckSetupStatusUseCase() -> PCheckSetupStatusUseCase {
        CheckSetupStatusUseCase(setupRepository: setupRepository)
    }
    
    func makeClearSetupConfigurationUseCase() -> PClearSetupConfigurationUseCase {
        ClearSetupConfigurationUseCase(
            setupRepository: setupRepository,
            configurationService: DefaultConfigurationService.shared
        )
    }
    
    // MARK: - SFTP Use Cases
    
    func makeGetAllConnectionsUseCase() -> GetAllConnectionsUseCase {
        GetAllConnectionsUseCase(repository: sftpRepository)
    }
    
    func makeListDirectoryUseCase() -> ListDirectoryUseCase {
        ListDirectoryUseCase(connectionManager: sftpConnectionManager)
    }
    
    func makeUploadFileUseCase() -> UploadFileUseCase {
        UploadFileUseCase(connectionManager: sftpConnectionManager)
    }
    
    func makeTestConnectionUseCase() -> TestConnectionUseCase {
        TestConnectionUseCase(connectionManager: sftpConnectionManager)
    }
    
    func makeSaveConnectionUseCase() -> SaveConnectionUseCase {
        SaveConnectionUseCase(repository: sftpRepository)
    }
    
    func makeDeleteConnectionUseCase() -> DeleteConnectionUseCase {
        DeleteConnectionUseCase(repository: sftpRepository)
    }
    
    func makeManageDefaultConnectionUseCase() -> ManageDefaultConnectionUseCase {
        ManageDefaultConnectionUseCase(repository: sftpRepository)
    }
    
    func makeManageFavoriteDirectoriesUseCase() -> ManageFavoriteDirectoriesUseCase {
        ManageFavoriteDirectoriesUseCase(repository: sftpRepository)
    }
    
    func makeCreateSFTPDirectoryUseCase() -> CreateSFTPDirectoryUseCase {
        CreateSFTPDirectoryUseCase(connectionManager: sftpConnectionManager)
    }
    
    func makeCheckConnectionStatusUseCase() -> CheckConnectionStatusUseCase {
        CheckConnectionStatusUseCase(connectionManager: sftpConnectionManager)
    }
    
    func makeClearConnectionCacheUseCase() -> ClearConnectionCacheUseCase {
        ClearConnectionCacheUseCase(connectionManager: sftpConnectionManager)
    }
    
    func makeGetCredentialsUseCase() -> GetCredentialsUseCase {
        GetCredentialsUseCase(repository: sftpRepository)
    }
    
    // MARK: - UI Use Cases
    
    lazy var fileSystemService: PFileSystemService = DefaultFileSystemService()
    lazy var viewModePreferenceRepository: PViewModePreferenceRepository = UserDefaultsViewModePreferenceStore()

    func makeGetViewModeUseCase() -> PGetViewModeUseCase {
        GetViewModeUseCase(repository: viewModePreferenceRepository)
    }

    func makeSaveViewModeUseCase() -> PSaveViewModeUseCase {
        SaveViewModeUseCase(repository: viewModePreferenceRepository)
    }

    func makeGetGroupRomsUseCase() -> PGetGroupRomsUseCase {
        GetGroupRomsUseCase()
    }

    func makeSaveGroupRomsUseCase() -> PSaveGroupRomsUseCase {
        SaveGroupRomsUseCase()
    }
    
    // MARK: - SFTP ViewModels
    
    @MainActor func makeSFTPDevicesViewModel() -> SFTPDevicesViewModel {
        SFTPDevicesViewModel()
    }
    
    @MainActor func makeSFTPDirectoryBrowserViewModel(connection: SFTPConnection) -> SFTPDirectoryBrowserViewModel {
        SFTPDirectoryBrowserViewModel(
            connection: connection,
            factory: self
        )
    }

    @MainActor func makeSFTPUploadViewModel(rom: Rom, autoStartLocalDownload: Bool = false) -> SFTPUploadViewModel {
        SFTPUploadViewModel(
            rom: rom,
            autoStartLocalDownload: autoStartLocalDownload,
            factory: self
        )
    }

    @MainActor func makeAddEditSFTPDeviceViewModel(connection: SFTPConnection?) -> AddEditSFTPDeviceViewModel {
        AddEditSFTPDeviceViewModel(
            connection: connection,
            factory: self
        )   
    }
    
    func makeSaveTransferHistoryUseCase() -> SaveTransferHistoryUseCase {
        .init(repository: transferHistoryRepository)
    }
    
    func makeGetTransferHistoryUseCase() -> GetTransferHistoryUseCase {
        .init(repository: transferHistoryRepository)
    }
    
    func makeGetTransferHistoryGroupedByPlatformUseCase() -> GetTransferHistoryGroupedByPlatformUseCase {
        .init(repository: transferHistoryRepository)
    }
    
    func makeClearTransferHistoryUseCase() -> ClearTransferHistoryUseCase {
        .init(repository: transferHistoryRepository)
    }
    
    func makeCheckEmulatorSupportUseCase() -> PCheckEmulatorSupportUseCase {
        CheckEmulatorSupportUseCase()
    }

    func makePlatformEngineSupport() -> PPlatformEngineSupport {
        PlatformEngineSupport()
    }

    func makeLaunchEmulatorUseCase() -> PLaunchEmulatorUseCase {
        LaunchEmulatorUseCase(
            tokenProvider: tokenProvider,
            checkEmulatorSupport: makeCheckEmulatorSupportUseCase(),
            enginePreference: enginePreference,
            platformSupport: makePlatformEngineSupport()
        )
    }

    lazy var saveStore: PSaveStore = LocalSaveStoreRepository()
    lazy var cloudSaveSyncStore: PCloudSaveSyncStore = CloudSaveSyncSettings.shared
    lazy var syncDeviceRepository: PSyncDeviceRepository = SyncDeviceRepository(
        apiClient: apiClient,
        heartbeat: heartbeatRepository
    )

    func makeGetDownloadedROMUseCase() -> PGetDownloadedROMUseCase {
        GetDownloadedROMUseCase(localROMRepository: localROMRepository)
    }

    func makeResolveROMFileUseCase() -> PResolveROMFileUseCase {
        ResolveROMFileUseCase(resolver: ROMFileResolver(fileSystem: fileSystemService))
    }

    func makeResolveExternalGameIdentifierUseCase() -> PResolveExternalGameIdentifierUseCase {
        ResolveExternalGameIdentifierUseCase(resolver: ROMFileResolver(fileSystem: fileSystemService))
    }

    func makeEmulatorSaveStatesUseCase() -> PEmulatorSaveStatesUseCase {
        EmulatorSaveStatesUseCase(saveStore: saveStore)
    }

    func makeSyncPreviewUseCase() -> PSyncPreviewUseCase {
        SyncPreviewUseCase(
            saveStore: saveStore,
            syncDevice: syncDeviceRepository,
            apiClient: apiClient,
            tokenProvider: tokenProvider
        )
    }

    lazy var externalSaveFolderStore: PExternalSaveFolderStore = UserDefaultsExternalSaveFolderStore()
    lazy var externalEmulatorSetupStore: PExternalEmulatorSetupStore = UserDefaultsExternalEmulatorSetupStore()

    func makeScanExternalSavesUseCase() -> PScanExternalSavesUseCase {
        ScanExternalSavesUseCase(
            folderStore: externalSaveFolderStore,
            localROMs: localROMRepository,
            handoffStore: externalEmulatorHandoffStore
        )
    }

    func makeBIOSSyncUseCase() -> PBIOSSyncUseCase {
        BIOSSyncUseCase(apiClient: apiClient, fileSystem: fileSystemService)
    }

    lazy var tokenProvider: PTokenProvider = TokenProvider()
    lazy var savesRepository: PSavesRepository = SavesRepository(apiClient: apiClient)
    lazy var statesRepository: PStatesRepository = StatesRepository(apiClient: apiClient)

    @MainActor func makeCloudSaveSyncService(romId: Int, emulator: String, batteryFileName: String) -> CloudSaveSyncService {
        CloudSaveSyncService(
            config: .init(romId: romId, emulator: emulator, batteryFileName: batteryFileName),
            saveStore: saveStore,
            listSavesUseCase: ListServerSavesUseCase(repository: savesRepository),
            uploadSaveUseCase: UploadSaveUseCase(repository: savesRepository),
            updateSaveUseCase: UpdateSaveUseCase(repository: savesRepository),
            downloadSaveUseCase: DownloadSaveUseCase(repository: savesRepository),
            listStatesUseCase: ListServerStatesUseCase(repository: statesRepository),
            uploadStateUseCase: UploadStateUseCase(repository: statesRepository),
            updateStateUseCase: UpdateStateUseCase(repository: statesRepository),
            downloadStateUseCase: DownloadStateUseCase(repository: statesRepository),
            apiClient: apiClient,
            syncDevice: syncDeviceRepository
        )
    }

    @MainActor func makeLibretroEmulatorViewModel(rom: Rom, core: LibretroCore) -> LibretroEmulatorViewModel {
        LibretroEmulatorViewModel(
            rom: rom,
            core: core,
            getDownloadedROM: makeGetDownloadedROMUseCase(),
            resolveROMFile: makeResolveROMFileUseCase(),
            saveStates: makeEmulatorSaveStatesUseCase(),
            biosSync: makeBIOSSyncUseCase(),
            aspectRatioPreference: libretroAspectRatioPreference,
            screenPositionPreference: emulatorScreenPositionPreference,
            menuShortcutPreference: emulatorMenuShortcutPreference,
            factory: self
        )
    }

    // MARK: - Save/State Sync Use Cases

    func makeListServerSavesUseCase() -> PListServerSavesUseCase { ListServerSavesUseCase(repository: savesRepository) }
    func makeListServerStatesUseCase() -> PListServerStatesUseCase { ListServerStatesUseCase(repository: statesRepository) }
    func makeDownloadSaveUseCase() -> PDownloadSaveUseCase { DownloadSaveUseCase(repository: savesRepository) }
    func makeDownloadStateUseCase() -> PDownloadStateUseCase { DownloadStateUseCase(repository: statesRepository) }
    func makeUploadSaveUseCase() -> PUploadSaveUseCase { UploadSaveUseCase(repository: savesRepository) }
    func makeUpdateSaveUseCase() -> PUpdateSaveUseCase { UpdateSaveUseCase(repository: savesRepository) }
    func makeUploadStateUseCase() -> PUploadStateUseCase { UploadStateUseCase(repository: statesRepository) }
    func makeUpdateStateUseCase() -> PUpdateStateUseCase { UpdateStateUseCase(repository: statesRepository) }
    func makeRecordSyncUseCase() -> PRecordSyncUseCase { RecordSyncUseCase(store: cloudSaveSyncStore) }
    func makeGetLastSyncUseCase() -> PGetLastSyncUseCase { GetLastSyncUseCase(store: cloudSaveSyncStore) }

    func makeGetROMShareFilesUseCase() -> PGetROMShareFilesUseCase {
        GetROMShareFilesUseCase(localROMRepository: localROMRepository)
    }

    @MainActor func makeSyncSaveViewModel(rom: DownloadedROM) -> SyncSaveViewModel {
        SyncSaveViewModel(
            rom: rom,
            listSavesUseCase: makeListServerSavesUseCase(),
            listStatesUseCase: makeListServerStatesUseCase(),
            downloadSaveUseCase: makeDownloadSaveUseCase(),
            downloadStateUseCase: makeDownloadStateUseCase(),
            uploadSaveUseCase: makeUploadSaveUseCase(),
            updateSaveUseCase: makeUpdateSaveUseCase(),
            uploadStateUseCase: makeUploadStateUseCase(),
            updateStateUseCase: makeUpdateStateUseCase(),
            saveStore: saveStore,
            recordSyncUseCase: makeRecordSyncUseCase(),
            getLastSyncUseCase: makeGetLastSyncUseCase()
        )
    }

    @MainActor func makeShareROMViewModel(rom: DownloadedROM) -> ShareROMViewModel {
        ShareROMViewModel(rom: rom, getShareFilesUseCase: makeGetROMShareFilesUseCase())
    }
}
