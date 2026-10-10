//
//  InMemoryRomUploadSignInHintStore.swift
//  rommTests
//

import Foundation
@testable import romm

final class InMemoryRomUploadSignInHintStore: PRomUploadSignInHintStore, @unchecked Sendable {
    private(set) var hasShownMissingScopeHint = false
    private(set) var markShownCallCount = 0

    func markMissingScopeHintShown() {
        hasShownMissingScopeHint = true
        markShownCallCount += 1
    }
}
