//
//  GetLatestLibraryScanUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

class GetLatestLibraryScanUseCase {
    private let tasksRepository: PTasksRepository

    init(tasksRepository: PTasksRepository) {
        self.tasksRepository = tasksRepository
    }

    func execute() async throws -> LibraryScanStatus? {
        return try await tasksRepository.getLatestLibraryScan()
    }
}
