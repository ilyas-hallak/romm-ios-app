import Foundation

protocol PRecordLocalLastPlayedUseCase {
    func execute(romId: Int) throws
}

final class RecordLocalLastPlayedUseCase: PRecordLocalLastPlayedUseCase {
    private let localROMRepository: PLocalROMRepository

    init(localROMRepository: PLocalROMRepository) {
        self.localROMRepository = localROMRepository
    }

    func execute(romId: Int) throws {
        try localROMRepository.recordPlayed(romId: romId)
    }
}
