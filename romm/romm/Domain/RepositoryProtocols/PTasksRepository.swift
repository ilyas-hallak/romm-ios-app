//
//  PTasksRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

protocol PTasksRepository {
    /// The most recent library scan task, or `nil` when none has ever run.
    func getLatestLibraryScan() async throws -> LibraryScanStatus?
}
