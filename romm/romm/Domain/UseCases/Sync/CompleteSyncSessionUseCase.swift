import Foundation

protocol PCompleteSyncSessionUseCase {
    func execute(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws
}

/// Closes out a sync session opened by negotiate. Purely bookkeeping on the
/// server side, so a caller should treat a thrown error as a log warning
/// rather than a run failure.
final class CompleteSyncSessionUseCase: PCompleteSyncSessionUseCase {
    private let repository: PSyncDeviceRepository
    init(repository: PSyncDeviceRepository) { self.repository = repository }
    func execute(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {
        try await repository.completeSyncSession(
            sessionId: sessionId,
            operationsCompleted: operationsCompleted,
            operationsFailed: operationsFailed
        )
    }
}
