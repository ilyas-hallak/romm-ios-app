import Foundation

protocol PDeleteAllDownloadedROMsUseCase {
    func execute() throws
}

/// Removes every downloaded ROM with its files. Saves live in their own store
/// and are left alone.
final class DeleteAllDownloadedROMsUseCase: PDeleteAllDownloadedROMsUseCase {
    private let localROMRepository: PLocalROMRepository

    init(localROMRepository: PLocalROMRepository) {
        self.localROMRepository = localROMRepository
    }

    /// Keeps going past a ROM that cannot be removed and throws the first
    /// failure at the end, so one stuck folder does not keep the rest.
    func execute() throws {
        var firstError: Error?
        for rom in try localROMRepository.getAllDownloadedROMs() {
            do {
                try localROMRepository.deleteDownloadedROM(rom)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
