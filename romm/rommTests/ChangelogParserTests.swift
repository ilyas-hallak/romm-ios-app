import Testing
import Foundation
@testable import romm

struct ChangelogParserTests {

    // MARK: - Real-world format

    // The parser must survive the exact shape CHANGELOG.md uses, including the
    // "## Version X" group headers, "### Build N (date)" entry headings, and
    // freeform summary sections like "### Builds 40 to 46 (June to August 2026)".
    @Test func parsesVersionHeaderCorrectly() {
        let md = """
        ## Version 1.0

        ### Build 49 (2026-08-22)

        - Something new
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries.count == 1)
        #expect(entries[0].version == "1.0")
    }

    @Test func parsesBuildNumberAndDate() {
        let md = """
        ## Version 1.0

        ### Build 49 (2026-08-22)

        - Feature A
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries.count == 1)
        #expect(entries[0].build == 49)
        #expect(entries[0].date == "2026-08-22")
    }

    @Test func buildTitleIsSetCorrectly() {
        let md = """
        ## Version 1.0

        ### Build 49 (2026-08-22)

        - Feature A
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries[0].title == "Build 49")
    }

    @Test func bodyDoesNotContainHeadingLine() {
        let md = """
        ## Version 1.0

        ### Build 49 (2026-08-22)

        - Feature A
        - Feature B
        """
        let entries = ChangelogParser.parse(md)
        let body = entries[0].body
        #expect(!body.contains("Build 49"))
        #expect(body.contains("Feature A"))
        #expect(body.contains("Feature B"))
    }

    // MARK: - Summary sections (no single build number)

    // "### Builds 40 to 46" has no single build number so it must get build 0.
    // build 0 is the signal that this entry should not participate in the
    // "what's new" comparison but is still shown in the version history.
    @Test func summarySectionGetsBuildZero() {
        let md = """
        ## Version 1.0

        ### Builds 40 to 46 (June to August 2026)

        These were many builds.
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries.count == 1)
        #expect(entries[0].build == 0)
        #expect(entries[0].date == "June to August 2026")
    }

    @Test func earlierBuildsFooterGetsBuildZero() {
        let md = """
        ## Version 1.0

        ### Earlier builds

        The app launched with browsing.
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries[0].build == 0)
        #expect(entries[0].date == nil)
    }

    // MARK: - Entry order

    // Entries must stay in file order (newest-first), so the "order" field
    // reflects position rather than being sorted by build number.
    @Test func entriesKeepFileOrder() {
        let md = """
        ## Version 1.0

        ### Build 49 (2026-08-22)

        - Newest

        ### Build 48 (2026-08-21)

        - Second

        ### Build 47 (2026-08-19)

        - Third
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries.count == 3)
        #expect(entries[0].order == 0)
        #expect(entries[0].build == 49)
        #expect(entries[1].order == 1)
        #expect(entries[1].build == 48)
        #expect(entries[2].order == 2)
        #expect(entries[2].build == 47)
    }

    // MARK: - Edge cases

    @Test func emptyInputReturnsEmptyList() {
        let entries = ChangelogParser.parse("")
        #expect(entries.isEmpty)
    }

    @Test func unparsableInputWithNoHeadingsReturnsEmpty() {
        let entries = ChangelogParser.parse("Just a plain paragraph.\nNo headings at all.")
        #expect(entries.isEmpty)
    }

    @Test func multipleVersionGroupsWorkCorrectly() {
        let md = """
        ## Version 2.0

        ### Build 50 (2026-09-01)

        - V2 feature

        ## Version 1.0

        ### Build 49 (2026-08-22)

        - V1 feature
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries.count == 2)
        #expect(entries[0].version == "2.0")
        #expect(entries[0].build == 50)
        #expect(entries[1].version == "1.0")
        #expect(entries[1].build == 49)
    }

    // MARK: - Real CHANGELOG.md format

    // The actual CHANGELOG.md uses "## Version X" headers; the parser must strip
    // the "Version " prefix and keep only the semver number.
    @Test func versionPrefixIsStripped() {
        let md = """
        ## Version 1.0

        ### Build 6 (2025-11-16)

        - Initial release
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries[0].version == "1.0")
    }

    // An entry with no date parenthetical should have nil date rather than an
    // empty string - the UI uses nil to hide the date label.
    @Test func entryWithNoDateParenHasNilDate() {
        let md = """
        ## Version 1.0

        ### Build 13

        - No date on this one
        """
        let entries = ChangelogParser.parse(md)
        #expect(entries[0].build == 13)
        #expect(entries[0].date == nil)
    }

    // Trailing blank lines around the body must be stripped so the UI does not
    // render spurious whitespace at the top or bottom of a section.
    @Test func leadingAndTrailingBlankLinesAreStrippedFromBody() {
        let md = """
        ## Version 1.0

        ### Build 49 (2026-08-22)

        - Item one

        """
        let entries = ChangelogParser.parse(md)
        let body = entries[0].body
        #expect(!body.hasPrefix("\n"))
        #expect(!body.hasSuffix("\n"))
    }
}
