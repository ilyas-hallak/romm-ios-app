import Testing
import Foundation

@testable import romm

struct HelpDocumentTests {

    @Test func parsesSectionsAndEntries() {
        let markdown = """
        # Frequently Asked Questions

        ## Connecting

        ### Why does it fail?

        Because of reasons.

        ### And this one?

        Other reasons.

        ## Playing

        ### Where is the button?

        Down there.
        """

        let document = HelpDocument.parse(markdown)

        #expect(document.sections.count == 2)
        #expect(document.sections[0].title == "Connecting")
        #expect(document.sections[0].entries.count == 2)
        #expect(document.sections[0].entries[0].question == "Why does it fail?")
        #expect(document.sections[0].entries[0].answer == "Because of reasons.")
        #expect(document.sections[1].title == "Playing")
        #expect(document.sections[1].entries.count == 1)
    }

    /// The document title and any prose before the first question are not part
    /// of an answer and must not leak into one.
    @Test func dropsTitleAndTextOutsideEntries() {
        let markdown = """
        # Title

        Intro paragraph that belongs to nothing.

        ## Section

        Section blurb, also unattached.

        ### Question

        Answer.
        """

        let document = HelpDocument.parse(markdown)

        #expect(document.sections.count == 1)
        #expect(document.sections[0].entries.count == 1)
        #expect(document.sections[0].entries[0].answer == "Answer.")
    }

    /// Answers are Markdown and keep their structure, including blank lines
    /// between paragraphs, but not the padding around the whole block.
    @Test func keepsMarkdownInsideAnswers() {
        let markdown = """
        ## Section

        ### Question

        First paragraph.

        - one
        - two

        **Bold** ending.

        """

        let document = HelpDocument.parse(markdown)
        let answer = document.sections[0].entries[0].answer

        #expect(answer.hasPrefix("First paragraph."))
        #expect(answer.contains("- one\n- two"))
        #expect(answer.hasSuffix("**Bold** ending."))
    }

    /// A section that never got a question would render as an empty group.
    @Test func skipsSectionsWithoutEntries() {
        let markdown = """
        ## Empty section

        Just prose.

        ## Real section

        ### Question

        Answer.
        """

        let document = HelpDocument.parse(markdown)

        #expect(document.sections.count == 1)
        #expect(document.sections[0].title == "Real section")
    }

    /// Deeper headings are content, not questions: a `####` inside an answer
    /// must not split it into a new entry.
    @Test func treatsDeeperHeadingsAsAnswerContent() {
        let markdown = """
        ## Section

        ### Question

        Intro.

        #### A sub heading

        More text.
        """

        let document = HelpDocument.parse(markdown)

        #expect(document.sections[0].entries.count == 1)
        #expect(document.sections[0].entries[0].answer.contains("#### A sub heading"))
    }

    @Test func emptyDocumentIsEmpty() {
        #expect(HelpDocument.parse("").isEmpty)
        #expect(HelpDocument.parse("Just some text").isEmpty)
    }

    /// The real document has to survive the parser, otherwise the help screen is
    /// empty in exactly the situation it is needed.
    ///
    /// Read from the repository rather than the bundle on purpose: this is the
    /// same file that gets served from GitHub, so it is the one worth guarding.
    @Test func parsesTheShippedDocument() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // rommTests
            .deletingLastPathComponent()   // romm
            .deletingLastPathComponent()   // repository root
        let markdown = try String(contentsOf: root.appending(path: "FAQ.md"), encoding: .utf8)

        let document = HelpDocument.parse(markdown)

        #expect(!document.isEmpty)
        #expect(document.sections.allSatisfy { !$0.entries.isEmpty })
        // Every entry needs an answer, an empty one would expand into nothing.
        #expect(document.sections.flatMap(\.entries).allSatisfy { !$0.answer.isEmpty })
    }
}
