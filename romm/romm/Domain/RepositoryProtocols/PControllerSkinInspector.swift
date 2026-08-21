import Foundation

/// Reads a `.deltaskin` archive's metadata. Implemented on top of DeltaCore, so a
/// skin is only accepted when the emulator can actually load it.
protocol PControllerSkinInspector {
    func inspect(fileURL: URL) throws -> ControllerSkinInfo
}
