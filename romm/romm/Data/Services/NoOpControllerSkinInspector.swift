import Foundation

/// Stand-in for `DeltaControllerSkinInspector` in builds without the Delta
/// cores (`DELTA_CORES` unset). There is no DeltaCore to ask, so no
/// `.deltaskin` file can ever be inspected: `installedSkins()` swallows the
/// error and simply comes back empty, and an explicit import attempt fails
/// with a clear message instead of silently doing nothing.
final class NoOpControllerSkinInspector: PControllerSkinInspector {

    func inspect(fileURL: URL) throws -> ControllerSkinInfo {
        throw ControllerSkinError.unsupportedInThisBuild
    }
}
