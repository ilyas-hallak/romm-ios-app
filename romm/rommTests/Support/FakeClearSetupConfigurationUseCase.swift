//
//  FakeClearSetupConfigurationUseCase.swift
//  rommTests
//

import Foundation
@testable import romm

final class FakeClearSetupConfigurationUseCase: PClearSetupConfigurationUseCase, @unchecked Sendable {
    private(set) var executeCallCount = 0
    var error: Error?

    func execute() throws {
        executeCallCount += 1
        if let error { throw error }
    }
}
