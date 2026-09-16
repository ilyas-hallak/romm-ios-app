//
//  ScanCredentialsPromptPresenter.swift
//  romm
//
//  Created by Ilyas Hallak on 13.09.26.
//

import Foundation
import Observation

/// Turns the session provider's `credentials(retryReason:)` call into a sheet
/// and the user's answer back into a return value. Nothing but the sheet talks
/// to this, the scan flow itself never sees it.
@Observable
@MainActor
final class ScanCredentialsPromptPresenter: PScanCredentialsPrompt {
    var isPresented = false
    private(set) var retryReason: String?

    private var pending: CheckedContinuation<ScanCredentials?, Never>?

    nonisolated init() {}

    func credentials(retryReason: String?) async -> ScanCredentials? {
        // A second ask while one is still open answers the first with nothing,
        // so no caller is left waiting on a prompt that is being replaced.
        resume(with: nil)

        self.retryReason = retryReason
        isPresented = true

        return await withCheckedContinuation { continuation in
            pending = continuation
        }
    }

    func submit(username: String, password: String) {
        isPresented = false
        resume(with: ScanCredentials(username: username, password: password))
    }

    /// Called for every way the sheet can go away, the cancel button and a
    /// swipe alike, so a dismissed prompt never leaves the scan hanging.
    func cancel() {
        isPresented = false
        resume(with: nil)
    }

    private func resume(with credentials: ScanCredentials?) {
        guard let pending else { return }
        self.pending = nil
        pending.resume(returning: credentials)
    }
}
