//
//  DependencyFactory.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

protocol PDependencyFactory {
    // Repositories
    var authRepository: PAuthRepository { get }
    var romsRepository: PRomsRepository { get }
    var platformsRepository: PPlatformsRepository { get }
    var collectionsRepository: PCollectionsRepository { get }
    var setupRepository: PSetupRepository { get }
    var sftpRepository: PSFTPRepository { get }
    var fileSystemRepository: PFileSystemRepository { get }
    var transferHistoryRepository: PTransferHistoryRepository { get }
    var localROMRepository: PLocalROMRepository { get }
    var statsRepository: PStatsRepository { get }
    var heartbeatRepository: PHeartbeatRepository { get }

    // Services
    var sftpKeychainService: PSFTPKeychainService { get }
    var sftpService: PSFTPService { get }
    var sftpConnectionManager: SFTPConnectionManager { get }
    var apiClient: PRommAPIClient { get }
    var fileValidationService: PFileValidationService { get }
    var tokenProvider: PTokenProvider { get }
    var saveStore: PSaveStore { get }
    
    // Use Cases
    func makeLogoutUseCase() -> LogoutUseCase
    func makeGetCurrentUserUseCase() -> GetCurrentUserUseCase
    func makeGetRomsUseCase() -> GetRomsUseCase
    func makeGetRomsWithFiltersUseCase() -> GetRomsWithFiltersUseCase
    func makeGetRomDetailsUseCase() -> GetRomDetailsUseCase
    func makeToggleRomFavoriteUseCase() -> ToggleRomFavoriteUseCase
    func makeCheckRomFavoriteStatusUseCase() -> CheckRomFavoriteStatusUseCase
    func makeUpdateLastPlayedUseCase() -> PUpdateLastPlayedUseCase
    func makeSearchRomsUseCase() -> SearchRomsUseCase
    func makeLoadManualUseCase() -> LoadManualUseCase
    func makeGetPlatformsUseCase() -> GetPlatformsUseCase
    func makeAddPlatformUseCase() -> AddPlatformUseCase
    func makeGetStatsUseCase() -> GetStatsUseCase
    func makeGetHeartbeatUseCase() -> GetHeartbeatUseCase
    func makeCheckServerVersionUseCase() -> CheckServerVersionUseCase
    func makeClearServerVersionUseCase() -> ClearServerVersionUseCase
    func makeSaveServerVersionUseCase() -> SaveServerVersionUseCase
    func makeGetCollectionsUseCase() -> GetCollectionsUseCase
    func makeGetVirtualCollectionsUseCase() -> GetVirtualCollectionsUseCase
    func makeCreateCollectionUseCase() -> CreateCollectionUseCase
    func makeUpdateCollectionUseCase() -> UpdateCollectionUseCase
    func makeDeleteCollectionUseCase() -> DeleteCollectionUseCase
    
    // Setup Use Cases
    func makeSaveSetupConfigurationUseCase() -> PSaveSetupConfigurationUseCase
    func makeGetSetupConfigurationUseCase() -> PGetSetupConfigurationUseCase
    func makeCheckSetupStatusUseCase() -> PCheckSetupStatusUseCase
    func makeClearSetupConfigurationUseCase() -> PClearSetupConfigurationUseCase
    
    // SFTP Use Cases
    func makeGetAllConnectionsUseCase() -> GetAllConnectionsUseCase
    func makeListDirectoryUseCase() -> ListDirectoryUseCase
    func makeUploadFileUseCase() -> UploadFileUseCase
    func makeTestConnectionUseCase() -> TestConnectionUseCase
    func makeSaveConnectionUseCase() -> SaveConnectionUseCase
    func makeDeleteConnectionUseCase() -> DeleteConnectionUseCase
    func makeManageDefaultConnectionUseCase() -> ManageDefaultConnectionUseCase
    func makeManageFavoriteDirectoriesUseCase() -> ManageFavoriteDirectoriesUseCase
    func makeCreateSFTPDirectoryUseCase() -> CreateSFTPDirectoryUseCase
    func makeCheckConnectionStatusUseCase() -> CheckConnectionStatusUseCase
    func makeClearConnectionCacheUseCase() -> ClearConnectionCacheUseCase
    func makeGetCredentialsUseCase() -> GetCredentialsUseCase

    // Transfer History Use Cases
    func makeSaveTransferHistoryUseCase() -> SaveTransferHistoryUseCase
    func makeGetTransferHistoryUseCase() -> GetTransferHistoryUseCase
    func makeGetTransferHistoryGroupedByPlatformUseCase() -> GetTransferHistoryGroupedByPlatformUseCase
    func makeClearTransferHistoryUseCase() -> ClearTransferHistoryUseCase
    
    // UI Use Cases
    func makeGetViewModeUseCase() -> PGetViewModeUseCase
    func makeSaveViewModeUseCase() -> PSaveViewModeUseCase
    func makeGetGroupRomsUseCase() -> PGetGroupRomsUseCase
    func makeSaveGroupRomsUseCase() -> PSaveGroupRomsUseCase

    // Save/State Sync Use Cases
    func makeListServerSavesUseCase() -> PListServerSavesUseCase
    func makeListServerStatesUseCase() -> PListServerStatesUseCase
    func makeDownloadSaveUseCase() -> PDownloadSaveUseCase
    func makeDownloadStateUseCase() -> PDownloadStateUseCase
    func makeUploadSaveUseCase() -> PUploadSaveUseCase
    func makeUpdateSaveUseCase() -> PUpdateSaveUseCase
    func makeUploadStateUseCase() -> PUploadStateUseCase
    func makeUpdateStateUseCase() -> PUpdateStateUseCase
    func makeRecordSyncUseCase() -> PRecordSyncUseCase
    func makeGetLastSyncUseCase() -> PGetLastSyncUseCase

    // Local ROM Use Cases
    func makeGetROMShareFilesUseCase() -> PGetROMShareFilesUseCase

    // Emulator Use Cases
    func makeCheckEmulatorSupportUseCase() -> PCheckEmulatorSupportUseCase
    func makeLaunchEmulatorUseCase() -> PLaunchEmulatorUseCase
    func makeGetDownloadedROMUseCase() -> PGetDownloadedROMUseCase
    func makeResolveROMFileUseCase() -> PResolveROMFileUseCase
    func makeEmulatorSaveStatesUseCase() -> PEmulatorSaveStatesUseCase
    func makeBIOSSyncUseCase() -> PBIOSSyncUseCase
    @MainActor func makeCloudSaveSyncService(romId: Int, emulator: String, batteryFileName: String) -> CloudSaveSyncService
    @MainActor func makeLibretroEmulatorViewModel(rom: Rom, core: LibretroCore) -> LibretroEmulatorViewModel

    // Emulator Engine
    var enginePreference: PEmulatorEnginePreference { get }
    var libretroAspectRatioPreference: PLibretroAspectRatioPreference { get }
    var emulatorScreenPositionPreference: PEmulatorScreenPositionPreference { get }
    var emulatorMenuShortcutPreference: PEmulatorMenuShortcutPreference { get }
    var externalDisplayPreference: PExternalDisplayPreference { get }
    var screenBrightness: PScreenBrightness { get }
    func makePlatformEngineSupport() -> PPlatformEngineSupport
    func makeControllerSkinsUseCase() -> PControllerSkinsUseCase

    // SFTP ViewModels
    @MainActor func makeSFTPDevicesViewModel() -> SFTPDevicesViewModel
    @MainActor func makeSFTPDirectoryBrowserViewModel(connection: SFTPConnection) -> SFTPDirectoryBrowserViewModel
    @MainActor func makeSFTPUploadViewModel(rom: Rom, autoStartLocalDownload: Bool) -> SFTPUploadViewModel
    @MainActor func makeAddEditSFTPDeviceViewModel(connection: SFTPConnection?) -> AddEditSFTPDeviceViewModel

    // Local ROM ViewModels
    @MainActor func makeSyncSaveViewModel(rom: DownloadedROM) -> SyncSaveViewModel
    @MainActor func makeShareROMViewModel(rom: DownloadedROM) -> ShareROMViewModel
}

class DefaultDependencyFactory: PDependencyFactory {
    func makeSFTPDevicesViewModel() -> SFTPDevicesViewModel {
        SFTPDevicesViewModel()
    }
    
    static let shared = DefaultDependencyFactory()
    
    // MARK: - Repositories (Singletons)
    
    lazy var authRepository: PAuthRepository = AuthRepository()
    lazy var romsRepository: PRomsRepository = RomsRepository()
    lazy var platformsRepository: PPlatformsRepository = PlatformsRepository()
    lazy var collectionsRepository: PCollectionsRepository = CollectionsRepository()
    lazy var setupRepository: PSetupRepository = SetupRepository()
    lazy var fileSystemRepository: PFileSystemRepository = FileSystemRepository()
    lazy var transferHistoryRepository: PTransferHistoryRepository = TransferHistoryRepository()
    lazy var localROMRepository: PLocalROMRepository = LocalROMRepository()
    lazy var statsRepository: PStatsRepository = StatsRepository()
    lazy var heartbeatRepository: PHeartbeatRepository = HeartbeatRepository()
    
    // MARK: - Services (Singletons)
    
    lazy var fileValidationService: PFileValidationService = FileValidationService()
    
    // MARK: - SFTP Services (Singletons)
    
    lazy var sftpKeychainService: PSFTPKeychainService = SFTPKeychainService()
    lazy var sftpRepository: PSFTPRepository = SFTPRepository(keychainService: sftpKeychainService)
    lazy var sftpService: PSFTPService = SFTPService(repository: sftpRepository)
    lazy var sftpConnectionManager: SFTPConnectionManager = {
        let manager = SFTPConnectionManager.shared
        manager.configure(with: sftpService)
        return manager
    }()
    lazy var apiClient: PRommAPIClient = RommAPIClient.shared
    lazy var tokenProvider: PTokenProvider = TokenProvider()

    private init() {}
    
    // MARK: - Auth Use Cases
    
    func makeLogoutUseCase() -> LogoutUseCase {
        LogoutUseCase(authRepository: authRepository)
    }
    
    func makeGetCurrentUserUseCase() -> GetCurrentUserUseCase {
        GetCurrentUserUseCase(authRepository: authRepository)
    }
    
    // MARK: - ROM Use Cases
    
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
    
    // MARK: - Platform Use Cases
    
    func makeGetPlatformsUseCase() -> GetPlatformsUseCase {
        GetPlatformsUseCase(platformsRepository: platformsRepository)
    }
    
    func makeAddPlatformUseCase() -> AddPlatformUseCase {
        AddPlatformUseCase(platformsRepository: platformsRepository)
    }

    // MARK: - Stats Use Cases

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

    // MARK: - Collection Use Cases
    
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
    
    // MARK: - Setup Use Cases
    
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

    // MARK: - Transfer History Use Cases

    func makeSaveTransferHistoryUseCase() -> SaveTransferHistoryUseCase {
        SaveTransferHistoryUseCase(repository: transferHistoryRepository)
    }

    func makeGetTransferHistoryUseCase() -> GetTransferHistoryUseCase {
        GetTransferHistoryUseCase(repository: transferHistoryRepository)
    }

    func makeGetTransferHistoryGroupedByPlatformUseCase() -> GetTransferHistoryGroupedByPlatformUseCase {
        GetTransferHistoryGroupedByPlatformUseCase(repository: transferHistoryRepository)
    }

    func makeClearTransferHistoryUseCase() -> ClearTransferHistoryUseCase {
        ClearTransferHistoryUseCase(repository: transferHistoryRepository)
    }

    // MARK: - UI Use Cases

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

    // MARK: - Emulator Use Cases

    func makeCheckEmulatorSupportUseCase() -> PCheckEmulatorSupportUseCase {
        CheckEmulatorSupportUseCase()
    }

    lazy var enginePreference: PEmulatorEnginePreference = UserDefaultsEmulatorEnginePreferenceStore()
    lazy var libretroAspectRatioPreference: PLibretroAspectRatioPreference = UserDefaultsLibretroAspectRatioPreferenceStore()
    lazy var emulatorScreenPositionPreference: PEmulatorScreenPositionPreference = UserDefaultsEmulatorScreenPositionPreferenceStore()
    lazy var emulatorMenuShortcutPreference: PEmulatorMenuShortcutPreference = UserDefaultsEmulatorMenuShortcutPreferenceStore()
    lazy var externalDisplayPreference: PExternalDisplayPreference = UserDefaultsExternalDisplayPreferenceStore()
    lazy var screenBrightness: PScreenBrightness = UIScreenBrightness()

    // MARK: - Controller Skins

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
    lazy var savesRepository: PSavesRepository = SavesRepository()
    lazy var statesRepository: PStatesRepository = StatesRepository()
    lazy var fileSystemService: PFileSystemService = DefaultFileSystemService()
    lazy var viewModePreferenceRepository: PViewModePreferenceRepository = UserDefaultsViewModePreferenceStore()
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

    func makeEmulatorSaveStatesUseCase() -> PEmulatorSaveStatesUseCase {
        EmulatorSaveStatesUseCase(saveStore: saveStore)
    }

    func makeBIOSSyncUseCase() -> PBIOSSyncUseCase {
        BIOSSyncUseCase(apiClient: apiClient, fileSystem: fileSystemService)
    }

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

    // MARK: - Save/State Sync Use Cases

    func makeListServerSavesUseCase() -> PListServerSavesUseCase {
        ListServerSavesUseCase(repository: savesRepository)
    }

    func makeListServerStatesUseCase() -> PListServerStatesUseCase {
        ListServerStatesUseCase(repository: statesRepository)
    }

    func makeDownloadSaveUseCase() -> PDownloadSaveUseCase {
        DownloadSaveUseCase(repository: savesRepository)
    }

    func makeDownloadStateUseCase() -> PDownloadStateUseCase {
        DownloadStateUseCase(repository: statesRepository)
    }

    func makeUploadSaveUseCase() -> PUploadSaveUseCase {
        UploadSaveUseCase(repository: savesRepository)
    }

    func makeUpdateSaveUseCase() -> PUpdateSaveUseCase {
        UpdateSaveUseCase(repository: savesRepository)
    }

    func makeUploadStateUseCase() -> PUploadStateUseCase {
        UploadStateUseCase(repository: statesRepository)
    }

    func makeUpdateStateUseCase() -> PUpdateStateUseCase {
        UpdateStateUseCase(repository: statesRepository)
    }

    func makeRecordSyncUseCase() -> PRecordSyncUseCase {
        RecordSyncUseCase(store: cloudSaveSyncStore)
    }

    func makeGetLastSyncUseCase() -> PGetLastSyncUseCase {
        GetLastSyncUseCase(store: cloudSaveSyncStore)
    }

    // MARK: - Local ROM Use Cases

    func makeGetROMShareFilesUseCase() -> PGetROMShareFilesUseCase {
        GetROMShareFilesUseCase(localROMRepository: localROMRepository)
    }

    // MARK: - Local ROM ViewModels

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

    // MARK: - SFTP ViewModels
    
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
}
