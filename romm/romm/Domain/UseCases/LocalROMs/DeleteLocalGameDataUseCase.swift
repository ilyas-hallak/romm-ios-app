import Foundation

protocol PDeleteLocalGameDataUseCase {
    func execute() throws
}

/// Removes every downloaded ROM with its files, and every save and save state
/// on this device, whether synced or not. The caller has to warn first.
final class DeleteLocalGameDataUseCase: PDeleteLocalGameDataUseCase {
    private let localROMRepository: PLocalROMRepository
    private let saveStore: PSaveStore

    init(localROMRepository: PLocalROMRepository, saveStore: PSaveStore) {
        self.localROMRepository = localROMRepository
        self.saveStore = saveStore
    }

    /// Keeps going past an item that cannot be removed and throws the first
    /// failure at the end, so one stuck folder does not keep the rest.
    func execute() throws {
        var firstError: Error?
        func attempt(_ delete: () throws -> Void) {
            do { try delete() } catch { firstError = firstError ?? error }
        }
        for rom in try localROMRepository.getAllDownloadedROMs() {
            attempt { try localROMRepository.deleteDownloadedROM(rom) }
        }
        for romId in try saveStore.listRomIds() {
            attempt { try saveStore.deleteSaves(romId: romId) }
        }
        if let firstError { throw firstError }
    }
}
