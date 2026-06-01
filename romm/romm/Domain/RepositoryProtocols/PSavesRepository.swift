import Foundation

protocol PSavesRepository {
    func listServerSaves(romId: Int) async throws -> [SaveSchema]
    func uploadSave(romId: Int, emulator: String?, slot: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
    func updateSave(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
    func downloadSave(id: Int) async throws -> Data
    func deleteSaves(ids: [Int]) async throws
}
