import Foundation

protocol PFindROMsByFileStemUseCase {
    /// Ids of the downloaded ROMs with a file named `stem`, extension and case
    /// ignored. Archives count by their own name, the files inside are unknown.
    func execute(stem: String) throws -> Set<Int>
}

final class FindROMsByFileStemUseCase: PFindROMsByFileStemUseCase {
    private let localROMRepository: PLocalROMRepository

    init(localROMRepository: PLocalROMRepository) {
        self.localROMRepository = localROMRepository
    }

    func execute(stem: String) throws -> Set<Int> {
        let wanted = stem.lowercased()
        let roms = try localROMRepository.getAllDownloadedROMs().filter { rom in
            rom.files.contains { ($0.fileName as NSString).deletingPathExtension.lowercased() == wanted }
        }
        return Set(roms.map(\.id))
    }
}
