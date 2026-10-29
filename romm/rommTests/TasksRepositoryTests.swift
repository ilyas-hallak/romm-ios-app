//
//  TasksRepositoryTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct TasksRepositoryTests {

    private static func schema(taskType: String, status: String) -> TaskStatusSchema {
        let json = """
        {
            "task_name": "Quick Scan",
            "task_id": "abc-123",
            "task_type": "\(taskType)",
            "status": "\(status)"
        }
        """
        return try! JSONDecoder().decode(TaskStatusSchema.self, from: Data(json.utf8))
    }

    @Test func picksTheFirstScanTaskOutOfSeveral() async throws {
        let apiClient = FakeAPIClient()
        apiClient.tasksStatusToReturn = [
            Self.schema(taskType: "cleanup", status: "finished"),
            Self.schema(taskType: "scan", status: "started")
        ]
        let repository = TasksRepository(apiClient: apiClient)

        let scan = try await repository.getLatestLibraryScan()

        #expect(scan?.state == .running)
    }

    @Test func aMissingScanTaskReadsAsNoScan() async throws {
        let apiClient = FakeAPIClient()
        apiClient.tasksStatusToReturn = []
        let repository = TasksRepository(apiClient: apiClient)

        let scan = try await repository.getLatestLibraryScan()

        #expect(scan == nil)
    }

    @Test func aForbiddenResponseMeansTheTokenIsMissingTheScope() async {
        // The account's role can carry `tasks.run` (which is what shows the
        // scan entry point) while the current sign-in's token does not, e.g. a
        // device-flow pairing from before the scope was requested. The server
        // then answers 403, which must not look like an ordinary failure.
        let apiClient = FakeAPIClient()
        apiClient.getTasksStatusError = APIClientError.invalidResponse(403, "Forbidden")
        let repository = TasksRepository(apiClient: apiClient)

        await #expect(throws: LibraryScanAccessError.missingScope) {
            try await repository.getLatestLibraryScan()
        }
    }

    @Test func anUnrelatedFailurePropagatesUnchanged() async {
        let apiClient = FakeAPIClient()
        apiClient.getTasksStatusError = APIClientError.invalidResponse(500, "boom")
        let repository = TasksRepository(apiClient: apiClient)

        await #expect(throws: APIClientError.self) {
            try await repository.getLatestLibraryScan()
        }
    }
}
