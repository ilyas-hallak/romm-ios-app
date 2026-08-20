import Foundation

enum ControllerSkinError: Error, LocalizedError, Equatable {
    case invalidURL
    case downloadFailed(statusCode: Int?)
    case notASkinFile
    case noSkinsOnPage
    case unsupportedGameType(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a valid link. Paste the direct link to a .deltaskin file."
        case .downloadFailed(let statusCode):
            if let statusCode {
                return "The download failed (HTTP \(statusCode)). Some skin sites block direct downloads. Save the file in Safari and use Import from Files instead."
            }
            return "The download failed. Check the link and your connection."
        case .notASkinFile:
            return "This file isn't a Delta controller skin."
        case .noSkinsOnPage:
            return "That page doesn't link to any .deltaskin files. Open a single skin's download link and paste that instead."
        case .unsupportedGameType(let gameType):
            return "This skin is made for a system the app can't emulate (\(gameType))."
        }
    }
}
