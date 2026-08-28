//
//  MockDependencyFactory.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//


// MARK: - Mock Factory for Testing

class MockDependencyFactory: PDependencyFactory {
    var transferHistoryRepository: PTransferHistoryRepository
    var localROMRepository: PLocalROMRepository

    // Mock repositories can be injected for testing
    var authRepository: PAuthRepository
    var romsRepository: PRomsRepository
    var platformsRepository: PPlatformsRepository
    var collectionsRepository: PCollectionsRepository
    var setupRepository: PSetupRepository
    var sftpRepository: PSFTPRepository
    var fileSystemRepository: PFileSystemRepository
    var statsRepository: PStatsRepository
    var heartbeatRepository: PHeartbeatRepository

    // Mock services
    var sftpKeychainService: PSFTPKeychainService
    var sftpService: PSFTPService
    var sftpConnectionManager: SFTPConnectionManager
    var apiClient: PRommAPIClient
    var fileValidationService: PFileValidationService

    // Emulator engine
    lazy var enginePreference: PEmulatorEnginePreference = UserDefaultsEmulatorEnginePreferenceStore()
    lazy var libretroAspectRatioPreference: PLibretroAspectRatioPreference = InMemoryLibretroAspectRatioPreference()
    lazy var emulatorScreenPositionPreference: PEmulatorScreenPositionPreference = InMemoryEmulatorScreenPositionPreference()
    lazy var emulatorMenuShortcutPreference: PEmulatorMenuShortcutPreference = UserDefaultsEmulatorMenuShortcutPreferenceStore()
    lazy var gamepadFaceButtonPreference: PGamepadFaceButtonPreference = UserDefaultsGamepadFaceButtonPreferenceStore()
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
        sftpKeychainService: PSFTPKeychainService? = nil,
        sftpService: PSFTPService? = nil,
        sftpConnectionManager: SFTPConnectionManager? = nil,
        apiClient: PRommAPIClient? = nil,
        fileValidationService: PFileValidationService? = nil
    ) {
        // Use provided mocks or default to real implementations
        self.authRepository = authRepository ?? AuthRepository()
        self.romsRepository = romsRepository ?? RomsRepository()
        self.platformsRepository = platformsRepository ?? PlatformsRepository()
        self.collectionsRepository = collectionsRepository ?? CollectionsRepository()
        self.setupRepository = setupRepository ?? SetupRepository()
        self.fileSystemRepository = fileSystemRepository ?? FileSystemRepository()
        self.statsRepository = statsRepository ?? StatsRepository()
        self.heartbeatRepository = HeartbeatRepository()

        let keychainService = sftpKeychainService ?? SFTPKeychainService()
        self.sftpKeychainService = keychainService
        self.sftpRepository = sftpRepository ?? SFTPRepository(keychainService: keychainService)
        self.fileValidationService = fileValidationService ?? FileValidationService()
        self.sftpService = sftpService ?? SFTPService(repository: self.sftpRepository)
        
        if let providedManager = sftpConnectionManager {
            self.sftpConnectionManager = providedManager
        } else {
            let manager = SFTPConnectionManager.shared
            manager.configure(with: self.sftpService)
            self.sftpConnectionManager = manager
        }
        
        self.apiClient = apiClient ?? RommAPIClient.shared
        transferHistoryRepository = TransferHistoryRepository()
        localROMRepository = LocalROMRepository()
    }
    
    func makeLogoutUseCase() -> LogoutUseCase {
        LogoutUseCase(authRepository: authRepository)
    }
    
    func makeGetCurrentUserUseCase() -> GetCurrentUserUseCase {
        GetCurrentUserUseCase(authRepository: authRepository)
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
    
    func makeLoadManualUseCase() -> LoadManualUseCase {
        LoadManualUseCase()
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
