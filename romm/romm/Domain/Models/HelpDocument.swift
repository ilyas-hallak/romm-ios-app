import Foundation

/// The help document, split into collapsible entries.
///
/// The Markdown structure carries the meaning, so no custom syntax is needed and
/// `FAQ.md` stays a normal document that reads fine on GitHub:
/// `##` opens a section, `###` is a question, everything below it is the answer.
struct HelpDocument: Equatable {
    let sections: [HelpSection]

    var isEmpty: Bool { sections.isEmpty }
}

struct HelpSection: Equatable, Identifiable {
    let title: String
    let entries: [HelpEntry]

    var id: String { title }
}

struct HelpEntry: Equatable, Identifiable {
    let question: String
    /// The answer as Markdown, rendered as-is.
    let answer: String

    var id: String { question }
}

extension HelpDocument {

    /// Parses the document. Anything before the first `##` is dropped, which is
    /// how the leading `# Frequently Asked Questions` title disappears without
    /// having to special-case it.
    static func parse(_ markdown: String) -> HelpDocument {
        var sections: [HelpSection] = []
        var sectionTitle: String?
        var entries: [HelpEntry] = []
        var question: String?
        var answer: [String] = []

        func flushEntry() {
            guard let question else { return }
            let text = answer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(HelpEntry(question: question, answer: text))
            answer = []
        }

        func flushSection() {
            flushEntry()
            question = nil
            guard let title = sectionTitle, !entries.isEmpty else {
                entries = []
                return
            }
            sections.append(HelpSection(title: title, entries: entries))
            entries = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            if let title = line.heading(level: 2) {
                flushSection()
                sectionTitle = title
            } else if let title = line.heading(level: 3) {
                flushEntry()
                question = title
            } else if question != nil {
                answer.append(line)
            }
            // Lines before the first question belong to no entry and are dropped.
        }
        flushSection()

        return HelpDocument(sections: sections)
    }
}

private extension String {

    /// The text of an ATX heading of exactly `level`, or `nil` for any other line.
    /// The trailing space in the marker is what keeps `###` from answering a
    /// request for level 2.
    func heading(level: Int) -> String? {
        let marker = String(repeating: "#", count: level) + " "
        guard hasPrefix(marker) else { return nil }
        let text = String(dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
