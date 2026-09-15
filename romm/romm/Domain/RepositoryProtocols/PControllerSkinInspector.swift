import Foundation

/// Reads a `.deltaskin` archive's metadata. The default implementation is
/// built on DeltaCore, so a skin is only accepted when the emulator can
/// actually load it; builds without Delta cores fall back to an inspector
/// that rejects every file instead.
protocol PControllerSkinInspector {
    func inspect(fileURL: URL) throws -> ControllerSkinInfo
}
