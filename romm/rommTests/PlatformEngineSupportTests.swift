import Testing
@testable import romm

struct PlatformEngineSupportTests {
    @Test func gbaSupportsBothEngines() {
        let support = PlatformEngineSupport()
        let engines = support.supportedEngines(for: "gba")
        #expect(engines.contains(.native))
        #expect(engines.contains(.web))
    }

    /// PlayStation used to be web only. It gained a libretro core
    /// (pcsx_rearmed), which the native engine covers alongside DeltaCore.
    @Test func psxSupportsBothEngines() {
        let support = PlatformEngineSupport()
        let engines = support.supportedEngines(for: "psx")
        #expect(engines.contains(.web))
        #expect(engines.contains(.native))
    }

    @Test func unknownPlatformReturnsEmpty() {
        let support = PlatformEngineSupport()
        #expect(support.supportedEngines(for: "xyz").isEmpty)
    }

    @Test func preferredFallsBackToWebForGBA() {
        let support = PlatformEngineSupport()
        #expect(support.preferred(for: "gba") == .web)
    }

    @Test func slugIsCaseInsensitive() {
        let support = PlatformEngineSupport()
        #expect(support.supportedEngines(for: "GBA").contains(.native))
    }
}
