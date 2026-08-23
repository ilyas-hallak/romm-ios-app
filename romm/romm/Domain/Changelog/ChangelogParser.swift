//
//  ChangelogParser.swift
//  romm
//
//  Created by Ilyas Hallak on 23.08.25.
//

import Foundation

enum ChangelogParser {
    /// Parses the CHANGELOG.md format.
    ///
    /// `## Version X` opens a version group, `### ...` opens an entry. A heading of
    /// the form `### Build 49 (2026-08-22)` carries a build number; any other `###`
    /// heading becomes an entry with build 0, which keeps summary sections such as
    /// `### Builds 40 to 46` visible in the version history while excluding them
    /// from the "what's new" comparison.
    ///
    /// Entries keep their order in the file, so the changelog has to be authored
    /// newest-first.
    static func parse(_ markdown: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        var currentVersion: String = "1.0"

        var currentBuild: Int?
        var currentDate: String?
        var currentTitle: String?
        var currentBodyLines: [String] = []

        let buildPattern = /^Build\s+(\d+)\s*$/
        let headingPattern = /^(.*?)(?:\s*\(([^)]*)\))?\s*$/

        func flushEntry() {
            guard let title = currentTitle else { return }
            let body = currentBodyLines
                .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .reversed()
                .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .reversed()
                .joined(separator: "\n")
            entries.append(ChangelogEntry(
                build: currentBuild ?? 0,
                version: currentVersion,
                date: currentDate,
                body: body,
                title: title,
                order: entries.count
            ))
            currentBuild = nil
            currentDate = nil
            currentTitle = nil
            currentBodyLines = []
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                flushEntry()
                // "## Version 1.0" -> "1.0"
                let versionText = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if versionText.lowercased().hasPrefix("version ") {
                    currentVersion = String(versionText.dropFirst("version ".count))
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    currentVersion = versionText
                }
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushEntry()
                let heading = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)

                // Split a trailing "(...)" off the heading and keep it as the date label.
                var name = heading
                if let match = heading.firstMatch(of: headingPattern) {
                    name = String(match.1).trimmingCharacters(in: .whitespaces)
                    if let label = match.2 {
                        let text = String(label).trimmingCharacters(in: .whitespaces)
                        currentDate = text.isEmpty ? nil : text
                    }
                }

                currentTitle = name
                if let build = name.firstMatch(of: buildPattern) {
                    currentBuild = Int(build.1)
                }
                continue
            }

            if currentTitle != nil {
                currentBodyLines.append(line)
            }
        }

        flushEntry()

        return entries
    }
}
