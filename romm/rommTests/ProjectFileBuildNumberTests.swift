import Testing
import Foundation
@testable import romm

/// Covers reading `CURRENT_PROJECT_VERSION` out of a project.pbxproj. This is the
/// only signal the update hint has, so a silent misread would either hide a real
/// update or announce one that does not exist.
struct ProjectFileBuildNumberTests {

    // MARK: - Realistic input

    // A trimmed but otherwise verbatim excerpt of romm.xcodeproj/project.pbxproj,
    // tabs and all. The setting sits between other build settings, so anything
    // that only worked on a clean single line would fail here.
    private let realExcerpt = """
    /* Begin XCBuildConfiguration section */
    		A1B2C3D4 /* Debug */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
    				CODE_SIGN_ENTITLEMENTS = romm/romm.entitlements;
    				CODE_SIGN_STYLE = Automatic;
    				CURRENT_PROJECT_VERSION = 41;
    				DEVELOPMENT_TEAM = 8J69P655GN;
    				ENABLE_HARDENED_RUNTIME = YES;
    				ENABLE_PREVIEWS = YES;
    				GENERATE_INFOPLIST_FILE = YES;
    				MARKETING_VERSION = 1.0;
    			};
    			name = Debug;
    		};
    /* End XCBuildConfiguration section */
    """

    @Test func readsBuildNumberFromRealProjectFileExcerpt() {
        #expect(ChangelogRepository.buildNumber(inProjectFile: realExcerpt) == 41)
    }

    // MARK: - Multiple occurrences

    // The setting appears once per build configuration and target, so a real file
    // has six or more copies. Fastlane keeps them in sync, but taking the highest
    // means a half-applied bump still reports the build that actually shipped.
    @Test func multipleOccurrencesReturnTheHighest() {
        let contents = """
        				CURRENT_PROJECT_VERSION = 41;
        				CURRENT_PROJECT_VERSION = 49;
        				CURRENT_PROJECT_VERSION = 47;
        """
        #expect(ChangelogRepository.buildNumber(inProjectFile: contents) == 49)
    }

    // The highest number wins regardless of where it sits, so the result does not
    // depend on the order Xcode happens to write the configurations in.
    @Test func highestWinsWhenItComesFirst() {
        let contents = """
        				CURRENT_PROJECT_VERSION = 50;
        				CURRENT_PROJECT_VERSION = 41;
        """
        #expect(ChangelogRepository.buildNumber(inProjectFile: contents) == 50)
    }

    // Every configuration carrying the same number is the normal case after a
    // clean bump, and must not be confused by the repetition.
    @Test func identicalOccurrencesReturnThatNumber() {
        let contents = Array(repeating: "\t\t\t\tCURRENT_PROJECT_VERSION = 41;", count: 6)
            .joined(separator: "\n")
        #expect(ChangelogRepository.buildNumber(inProjectFile: contents) == 41)
    }

    // MARK: - Nothing to find

    // 0 is the "could not read it" signal the use case turns into .notChecked,
    // so these must not accidentally produce a usable-looking number.
    @Test func noOccurrenceReturnsZero() {
        let contents = """
        				MARKETING_VERSION = 1.0;
        				SWIFT_VERSION = 5.0;
        """
        #expect(ChangelogRepository.buildNumber(inProjectFile: contents) == 0)
    }

    @Test func emptyInputReturnsZero() {
        #expect(ChangelogRepository.buildNumber(inProjectFile: "") == 0)
    }

    // An error page or a redirect body still arrives as a 200 with text, so
    // arbitrary content has to come back as 0 rather than something plausible.
    @Test func unrelatedContentReturnsZero() {
        #expect(ChangelogRepository.buildNumber(inProjectFile: "404: Not Found") == 0)
    }

    // MARK: - Numbers bordering other text

    // The number is read up to the first non-digit, so the trailing semicolon that
    // always follows in a pbxproj must not end up in the parsed value.
    @Test func trailingSemicolonIsNotPartOfTheNumber() {
        #expect(ChangelogRepository.buildNumber(inProjectFile: "CURRENT_PROJECT_VERSION = 41;") == 41)
    }

    // Without a trailing semicolon, for example at the very end of the file, the
    // number still has to be read rather than dropped.
    @Test func numberAtEndOfInputIsRead() {
        #expect(ChangelogRepository.buildNumber(inProjectFile: "CURRENT_PROJECT_VERSION = 41") == 41)
    }

    // A quoted value is valid pbxproj syntax and turns up after a hand edit.
    // Reading it anyway matters because the alternative is not an error but a
    // silently disabled update hint.
    @Test func quotedValueIsStillRead() {
        #expect(ChangelogRepository.buildNumber(inProjectFile: "CURRENT_PROJECT_VERSION = \"41\";") == 41)
    }

    // A non-numeric value, such as an unexpanded build setting reference, must not
    // be read as a partial number.
    @Test func nonNumericValueIsIgnored() {
        let contents = """
        				CURRENT_PROJECT_VERSION = $(INHERITED);
        				CURRENT_PROJECT_VERSION = 41;
        """
        #expect(ChangelogRepository.buildNumber(inProjectFile: contents) == 41)
    }

    // Text before and after the setting on the same line, which is legal in the
    // OpenStep plist format, must not bleed into the number.
    @Test func surroundingTextOnTheSameLineDoesNotBreakIt() {
        let contents = "buildSettings = { CURRENT_PROJECT_VERSION = 49; MARKETING_VERSION = 1.0; };"
        #expect(ChangelogRepository.buildNumber(inProjectFile: contents) == 49)
    }

    // A similarly named setting must not be picked up, otherwise an unrelated
    // number could masquerade as the build.
    @Test func similarlyNamedSettingIsNotMatched() {
        let contents = """
        				DYLIB_CURRENT_VERSION = 99;
        				CURRENT_PROJECT_VERSION = 41;
        """
        #expect(ChangelogRepository.buildNumber(inProjectFile: contents) == 41)
    }

    // Multi-digit builds are the norm by now, so a naive single-character read
    // would silently report a much older build.
    @Test func multiDigitBuildIsReadInFull() {
        #expect(ChangelogRepository.buildNumber(inProjectFile: "CURRENT_PROJECT_VERSION = 1234;") == 1234)
    }
}
