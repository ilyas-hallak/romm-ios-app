import Testing
@testable import romm

struct PlatformIconTests {

    @Test func pcengineResolvesToPceBeforeDefault() {
        let candidates = PlatformIcon.assetNameCandidates(for: "pcengine")

        #expect(candidates.contains("pce"))
        #expect(candidates.firstIndex(of: "pce")! < candidates.firstIndex(of: "default")!)
    }

    @Test func neogeoResolvesToNeogeoaes() {
        #expect(PlatformIcon.assetNameCandidates(for: "neogeo").contains("neogeoaes"))
    }

    @Test func mame2003ResolvesToArcade() {
        #expect(PlatformIcon.assetNameCandidates(for: "mame2003").contains("arcade"))
    }

    @Test func slugWithAnExistingAssetIsTheFirstCandidate() {
        #expect(PlatformIcon.assetNameCandidates(for: "snes").first == "snes")
    }

    @Test func nilSlugReturnsOnlyDefault() {
        #expect(PlatformIcon.assetNameCandidates(for: nil) == ["default"])
    }

    @Test func emptySlugReturnsOnlyDefault() {
        #expect(PlatformIcon.assetNameCandidates(for: "") == ["default"])
    }

    @Test func caseAndWhitespaceAreNormalized() {
        #expect(PlatformIcon.assetNameCandidates(for: "  SNES ").first == "snes")
    }

    @Test func separatorFreeVariantIsIncluded() {
        #expect(PlatformIcon.assetNameCandidates(for: "wii-u").contains("wiiu"))
    }

    @Test func everyCandidateListEndsInDefaultAndHasNoDuplicates() {
        let slugs = ["pcengine", "neogeo", "mame2003", "snes", "wii-u", "sg-1000", "unknown-thing"]

        for slug in slugs {
            let candidates = PlatformIcon.assetNameCandidates(for: slug)
            #expect(candidates.last == "default")
            #expect(candidates.count == Set(candidates).count)
        }
    }

    @Test func unknownSlugFallsBackToDefault() {
        #expect(PlatformIcon.assetNameCandidates(for: "totally-unknown-platform").last == "default")
    }

    /// Hits the asset catalog, unlike the candidate tests above.
    @MainActor
    @Test func hasIconOnlyForSlugsTheCatalogCovers() {
        #expect(PlatformIcon.hasIcon(for: "snes"))
        #expect(PlatformIcon.hasIcon(for: "totally-unknown-platform") == false)
        #expect(PlatformIcon.hasIcon(for: nil) == false)
    }
}
