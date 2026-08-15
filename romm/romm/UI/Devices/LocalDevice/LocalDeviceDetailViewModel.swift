import Foundation
import Observation

@MainActor
@Observable
class LocalDeviceDetailViewModel {
    var downloadedROMs: [DownloadedROM] = []
    var romsByPlatform: [String: [DownloadedROM]] = [:]
    var platformDisplayNamesBySlug: [String: String] = [:]
    var isLoading = false
    var error: String?
    var totalDownloadedSize: Int64 = 0
    var showingDeleteConfirmation = false
    var romToDelete: DownloadedROM?

    private let repository: PLocalROMRepository
    private let getPlatformsUseCase: GetPlatformsUseCase
    private let getLastSyncUseCase: PGetLastSyncUseCase

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.repository = factory.localROMRepository
        self.getPlatformsUseCase = factory.makeGetPlatformsUseCase()
        self.getLastSyncUseCase = factory.makeGetLastSyncUseCase()
    }

    func displayName(forPlatformName platformName: String) -> String {
        if let rom = romsByPlatform[platformName]?.first,
           let name = platformDisplayNamesBySlug[rom.platformSlug] {
            return name
        }
        return platformName
    }

    func loadPlatformDisplayNames() async {
        do {
            let platforms = try await getPlatformsUseCase.execute()
            var map: [String: String] = [:]
            for p in platforms {
                map[p.slug] = p.displayName
            }
            platformDisplayNamesBySlug = map
        } catch {
            // Non-fatal: fall back to stored platformName
        }
    }

    // MARK: - Public Methods

    /// Loads downloaded ROMs asynchronously to avoid blocking main thread
    func loadDownloadedROMsAsync() async {
        // Only show loading if we don't have data yet
        if downloadedROMs.isEmpty {
            isLoading = true
        }
        error = nil

        // Perform FileManager operations in background with higher priority for better responsiveness
        let result = await Task.detached(priority: .userInitiated) { [repository = self.repository] () -> Result<(roms: [DownloadedROM], byPlatform: [String: [DownloadedROM]], totalSize: Int64), Error> in
            do {
                // Optimize: Calculate everything in one pass
                let downloadedROMs = try repository.getAllDownloadedROMs()

                // Group by platform and calculate total size in single pass
                var romsByPlatform: [String: [DownloadedROM]] = [:]
                var totalSize: Int64 = 0

                for rom in downloadedROMs {
                    if romsByPlatform[rom.platformName] == nil {
                        romsByPlatform[rom.platformName] = []
                    }
                    romsByPlatform[rom.platformName]?.append(rom)
                    totalSize += rom.totalSizeBytes
                }

                return .success((downloadedROMs, romsByPlatform, totalSize))
            } catch {
                return .failure(error)
            }
        }.value

        // Update UI on main thread
        switch result {
        case .success(let data):
            self.downloadedROMs = data.roms
            self.romsByPlatform = data.byPlatform
            self.totalDownloadedSize = data.totalSize
        case .failure(let error):
            self.error = "Failed to load downloaded ROMs: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Legacy synchronous method - prefer loadDownloadedROMsAsync() for better performance
    @available(*, deprecated, message: "Use loadDownloadedROMsAsync() instead")
    func loadDownloadedROMs() {
        isLoading = true
        error = nil

        do {
            downloadedROMs = try repository.getAllDownloadedROMs()
            romsByPlatform = try repository.getDownloadedROMsByPlatform()
            totalDownloadedSize = try repository.getTotalDownloadedSize()
        } catch {
            self.error = "Failed to load downloaded ROMs: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func confirmDelete(_ rom: DownloadedROM) {
        romToDelete = rom
        showingDeleteConfirmation = true
    }

    func deleteROM(_ rom: DownloadedROM) {
        do {
            try repository.deleteDownloadedROM(rom)
            Task { await loadDownloadedROMsAsync() }
        } catch {
            self.error = "Failed to delete ROM: \(error.localizedDescription)"
        }
    }

    func refreshStorageInfo() async {
        await LocalDeviceManager.shared.updateStorageInfoAsync()
    }

    var totalDownloadedSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalDownloadedSize, countStyle: .file)
    }

    var platformNames: [String] {
        Array(romsByPlatform.keys).sorted()
    }

    var hasDownloadedROMs: Bool {
        !downloadedROMs.isEmpty
    }

    // MARK: - Sync metadata

    func lastSync(romId: Int) -> SyncMetadata? {
        getLastSyncUseCase.execute(romId: romId)
    }
}
