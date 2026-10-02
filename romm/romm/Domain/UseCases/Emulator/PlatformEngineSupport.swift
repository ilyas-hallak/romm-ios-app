import Foundation

protocol PPlatformEngineSupport {
    func supportedEngines(for platformSlug: String) -> Set<EmulatorEngine>
    func preferred(for platformSlug: String) -> EmulatorEngine
    /// Whether the platform can be emulated at all with the engines enabled in
    /// this build. False for web-only platforms when the web engine is disabled.
    func isEmulationAvailable(for platformSlug: String) -> Bool
}

final class PlatformEngineSupport: PPlatformEngineSupport {
    private let webSupport: PCheckEmulatorSupportUseCase

    init(webSupport: PCheckEmulatorSupportUseCase = CheckEmulatorSupportUseCase()) {
        self.webSupport = webSupport
    }

    func supportedEngines(for platformSlug: String) -> Set<EmulatorEngine> {
        #if APP_STORE
        // No engines ship in the App Store build: no Delta cores, no
        // libretro cores, no bundled EmulatorJS. Play always hands off to
        // an external emulator app instead.
        return []
        #else
        let slug = platformSlug.lowercased()
        var result: Set<EmulatorEngine> = []
        if AppFeatures.webEmulatorEnabled, webSupport.execute(platformSlug: slug) {
            result.insert(.web)
        }
        if PlatformSlugToGameType.map(slug) != nil || PlatformSlugToLibretroCore.map(slug) != nil {
            result.insert(.native)
        }
        return result
        #endif
    }

    func preferred(for platformSlug: String) -> EmulatorEngine {
        #if APP_STORE
        return .auto
        #else
        let supported = supportedEngines(for: platformSlug)
        return supported.contains(.web) ? .web : .native
        #endif
    }

    func isEmulationAvailable(for platformSlug: String) -> Bool {
        !supportedEngines(for: platformSlug).isEmpty
    }
}
