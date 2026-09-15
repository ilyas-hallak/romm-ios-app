import Testing
@testable import romm

// The server returns every page ordered by name, so grouping must not reorder anything.
// It used to sort each section again with Swift's ordinal comparison, which is a different
// collation than the server's. A ROM from a later page could therefore land between two
// ROMs that were already on screen, which pushed every following card into the other column
// of the two column grid.
struct RomSectionGroupingTests {

    private func makeRom(id: Int, name: String) -> Rom {
        Rom(id: id, name: name, platformId: 1)
    }

    @Test func sectionsFollowTheOrderTheRomsArrivedIn() {
        let roms = [
            makeRom(id: 1, name: "Adventure Island"),
            makeRom(id: 2, name: "aero Blasters"),
            makeRom(id: 3, name: "Air Zonk"),
        ]

        let sections = RomSection.sections(for: roms)

        #expect(sections.count == 1)
        #expect(sections[0].letter == "A")
        // Sorting with `<` would have moved "Air Zonk" ahead of "aero Blasters", because an
        // uppercase letter sorts before every lowercase one.
        #expect(sections[0].roms.map(\.id) == [1, 2, 3])
    }

    @Test func anAppendedPageNeverMovesWhatIsAlreadyOnScreen() {
        // The server's collation compares letters before case, so it returns "aero Blasters"
        // first and "Air Zonk" on the next page. Swift's `<` orders them the other way round,
        // which is what used to drag the first ROM one slot down once page two arrived.
        let firstPage = [
            makeRom(id: 1, name: "aero Blasters"),
            makeRom(id: 2, name: "Bomberman"),
        ]
        let secondPage = [
            makeRom(id: 3, name: "Air Zonk"),
            makeRom(id: 4, name: "Cadash"),
        ]

        let before = RomSection.sections(for: firstPage)
        let after = RomSection.sections(for: firstPage + secondPage)

        #expect(before[0].roms.map(\.id) == [1])
        #expect(after[0].roms.map(\.id) == [1, 3])
        #expect(after.map(\.letter) == ["A", "B", "C"])
        #expect(after[2].roms.map(\.id) == [4])
    }

    @Test func sectionOrderFollowsFirstAppearance() {
        let roms = [
            makeRom(id: 1, name: "Air Zonk"),
            makeRom(id: 2, name: "Bomberman"),
            makeRom(id: 3, name: "Cadash"),
        ]

        #expect(RomSection.sections(for: roms).map(\.letter) == ["A", "B", "C"])
    }

    @Test func namesThatDoNotStartWithALetterShareTheHashSection() {
        let roms = [
            makeRom(id: 1, name: "1943"),
            makeRom(id: 2, name: "Bomberman"),
            makeRom(id: 3, name: "007 Goldeneye"),
        ]

        let sections = RomSection.sections(for: roms)

        #expect(sections.map(\.letter) == ["#", "B"])
        #expect(sections[0].roms.map(\.id) == [1, 3])
    }

    @Test func lowercaseAndUppercaseShareOneSection() {
        let roms = [
            makeRom(id: 1, name: "Sonic"),
            makeRom(id: 2, name: "sonic 2"),
        ]

        let sections = RomSection.sections(for: roms)

        #expect(sections.count == 1)
        #expect(sections[0].letter == "S")
    }

    @Test func emptyInputProducesNoSections() {
        #expect(RomSection.sections(for: []).isEmpty)
    }
}
