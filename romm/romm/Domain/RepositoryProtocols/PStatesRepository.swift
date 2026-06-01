import Foundation

protocol PStatesRepository {
    func listServerStates(romId: Int) async throws -> [StateSchema]
    func uploadState(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema
    func updateState(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema
    func downloadState(id: Int) async throws -> Data
    func deleteStates(ids: [Int]) async throws
}
