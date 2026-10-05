import Foundation
import Observation

/// Drives the conflict-resolution sheet for one ROM's battery save: loads
/// both sides' stats, then hands the user's pick to `BatteryConflictResolver`.
@Observable
@MainActor
final class BatteryConflictViewModel: Identifiable {
    /// Identifies the sheet instance for `.sheet(item:)`; one ROM has at most
    /// one battery conflict, so its id is unique enough.
    var id: Int { romId }

    /// One side's stats for display. `deviceName` is only ever set on the
    /// server side, when the save names the device that uploaded it.
    struct Side: Equatable {
        let date: Date?
        let sizeBytes: Int?
        let deviceName: String?
    }

    enum State {
        case loading
        case ready(local: Side, server: Side)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isResolving = false
    var errorMessage: String?

    let romId: Int
    private let saveId: Int

    private let saveStore: PSaveStore
    private let listSavesUseCase: PListServerSavesUseCase
    private let resolver: PBatteryConflictResolver
    private let onResolved: () async -> Void

    init(
        romId: Int,
        saveId: Int,
        saveStore: PSaveStore,
        listSavesUseCase: PListServerSavesUseCase,
        resolver: PBatteryConflictResolver,
        onResolved: @escaping () async -> Void
    ) {
        self.romId = romId
        self.saveId = saveId
        self.saveStore = saveStore
        self.listSavesUseCase = listSavesUseCase
        self.resolver = resolver
        self.onResolved = onResolved
    }

    func load() async {
        state = .loading
        let localSide = Side(
            date: saveStore.batteryModifiedAt(romId: romId),
            sizeBytes: (try? saveStore.readBattery(romId: romId))?.count,
            deviceName: nil
        )
        do {
            guard let server = try await listSavesUseCase.execute(romId: romId).first(where: { $0.id == saveId }) else {
                state = .failed(String(localized: "The server save is no longer available."))
                return
            }
            let originName = server.deviceSyncs?.first { $0.deviceId == server.originDeviceId }?.deviceName
            let serverSide = Side(
                date: server.updatedAt,
                sizeBytes: server.fileSizeBytes,
                deviceName: originName ?? server.originDeviceId
            )
            state = .ready(local: localSide, server: serverSide)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Resolves the conflict in favor of this device's local file, then
    /// reports back through `onResolved` so the caller can refresh.
    func keepThisDevice() async {
        await resolve { try await self.resolver.keepThisDevice(romId: self.romId, saveId: self.saveId) }
    }

    /// Resolves the conflict in favor of the server's row, then reports back
    /// through `onResolved` so the caller can refresh.
    func keepServer() async {
        guard case .ready(_, let server) = state else { return }
        await resolve { try await self.resolver.keepServer(romId: self.romId, saveId: self.saveId, serverUpdatedAt: server.date) }
    }

    private func resolve(_ action: @escaping () async throws -> Void) async {
        isResolving = true
        defer { isResolving = false }
        do {
            try await action()
            await onResolved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
