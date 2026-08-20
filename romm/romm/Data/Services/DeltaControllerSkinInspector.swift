import Foundation
import DeltaCore

/// Reads a `.deltaskin` file's metadata by asking DeltaCore to open it, so a
/// skin is only accepted when the emulator can actually load it.
final class DeltaControllerSkinInspector: PControllerSkinInspector {

    func inspect(fileURL: URL) throws -> ControllerSkinInfo {
        guard let skin = ControllerSkin(fileURL: fileURL) else {
            throw ControllerSkinError.notASkinFile
        }

        let gameTypeIdentifier = skin.gameType.rawValue

        // Reject skins built for systems the app has no core for, so they never
        // show up as a pickable option.
        guard DeltaGameType(gameTypeIdentifier: gameTypeIdentifier) != nil else {
            throw ControllerSkinError.unsupportedGameType(gameTypeIdentifier)
        }

        return ControllerSkinInfo(
            fileName: fileURL.lastPathComponent,
            name: skin.name,
            identifier: skin.identifier,
            gameTypeIdentifier: gameTypeIdentifier
        )
    }
}
