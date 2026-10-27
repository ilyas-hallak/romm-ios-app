//
//  InMemorySaveSyncOutcomeStore.swift
//  rommTests
//

import Foundation
@testable import romm

/// Stand-in for the UserDefaults-backed store, so a test can seed the last run
/// and read back what a run recorded without touching the real settings.
final class InMemorySaveSyncOutcomeStore: PSaveSyncOutcomeStore, @unchecked Sendable {
    var outcome: SaveSyncOutcome?

    init(outcome: SaveSyncOutcome? = nil) {
        self.outcome = outcome
    }

    func recordRun(_ outcome: SaveSyncOutcome) { self.outcome = outcome }
    func lastRun() -> SaveSyncOutcome? { outcome }
}
