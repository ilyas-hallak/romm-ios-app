//
//  WhatsNewView.swift
//  romm
//
//  Created by Ilyas Hallak on 23.08.25.
//

import SwiftUI

// MARK: - WhatsNewView

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let entries: [ChangelogEntry]
    private let shouldMarkSeen: Bool
    private let title: LocalizedStringKey
    private let closeLabel: LocalizedStringKey

    /// - Parameters:
    ///   - entries: Entries to display. Pass `nil` to show unseen entries (default, auto-marks seen).
    ///              Pass an explicit array (e.g. `ChangelogStore.shared.entries`) to show all entries
    ///              without marking them seen (used from Settings).
    ///   - markSeenOnDismiss: Whether `ChangelogStore.shared.markSeen()` is called on dismiss.
    init(entries: [ChangelogEntry]? = nil, markSeenOnDismiss: Bool = true) {
        self.entries = entries ?? ChangelogStore.shared.unseenEntries
        self.shouldMarkSeen = markSeenOnDismiss
        // Presented automatically after an update it is a "what's new" note; opened
        // by hand from Settings it is the full history, so the framing differs.
        self.title = markSeenOnDismiss ? "What's New" : "Version History"
        self.closeLabel = markSeenOnDismiss ? "Continue" : "Done"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ChangelogEntryView(entry: entry)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                        if index < entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            // Without an explicit bar background the collapsed title has no
            // backdrop and the scrolling text runs straight through it.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(closeLabel) {
                        handleDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onDisappear {
                handleDismiss()
            }
        }
    }

    private func handleDismiss() {
        if shouldMarkSeen {
            ChangelogStore.shared.markSeen()
        }
    }
}

// MARK: - ChangelogEntryView

private struct ChangelogEntryView: View {
    let entry: ChangelogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: build number + date
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title)
                    .font(.title3)
                    .fontWeight(.bold)
                if let date = entry.date {
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Parsed body
            ChangelogBodyView(markdown: entry.body)
        }
    }
}

// MARK: - ChangelogBodyView

private struct ChangelogBodyView: View {
    let markdown: String

    private struct Group {
        let title: String
        let icon: String
        let color: Color
        let bullets: [String]
    }

    var body: some View {
        let groups = parseGroups(markdown)
        return VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty {
                // Summary sections are plain prose with no **New** / **Fixed** groups.
                ProseRow(text: markdown)
            }
            ForEach(groups.indices, id: \.self) { index in
                let section = groups[index]
                VStack(alignment: .leading, spacing: 8) {
                    // Section header
                    Label(section.title, systemImage: section.icon)
                        .font(.headline)
                        .foregroundStyle(section.color)

                    // Bullets
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(section.bullets.indices, id: \.self) { bulletIndex in
                            BulletRow(text: section.bullets[bulletIndex])
                        }
                    }
                }
            }
        }
    }

    // MARK: - Parsing

    private func parseGroups(_ markdown: String) -> [Group] {
        var result: [Group] = []
        var currentTitle: String?
        var currentBullets: [String] = []

        func flush() {
            guard let title = currentTitle, !currentBullets.isEmpty else { return }
            let (icon, color) = iconAndColor(for: title)
            result.append(Group(title: title, icon: icon, color: color, bullets: currentBullets))
            currentBullets = []
            currentTitle = nil
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Group headers are written as **New**, **Fixed**, etc.
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && !trimmed.hasPrefix("**-") {
                flush()
                currentTitle = String(trimmed.dropFirst(2).dropLast(2))
            } else if trimmed.hasPrefix("- ") {
                currentBullets.append(String(trimmed.dropFirst(2)))
            } else if currentTitle != nil {
                // Continuation lines (e.g. second sentence of a bullet that wrapped)
                if var last = currentBullets.last {
                    currentBullets.removeLast()
                    last += " " + trimmed
                    currentBullets.append(last)
                } else {
                    currentBullets.append(trimmed)
                }
            }
        }
        flush()
        return result
    }

    private func iconAndColor(for title: String) -> (String, Color) {
        switch title.lowercased() {
        case "new":
            return ("sparkles", .green)
        case "improved":
            return ("wand.and.stars", .blue)
        case "fixed":
            return ("wrench.and.screwdriver", .orange)
        case "known issues":
            return ("exclamationmark.triangle", .secondary)
        default:
            return ("list.bullet", .primary)
        }
    }
}

// MARK: - ProseRow

/// Renders a section that is plain prose instead of grouped bullets. Single
/// newlines are soft wraps in the source, blank lines separate paragraphs.
private struct ProseRow: View {
    let text: String

    var body: some View {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        VStack(alignment: .leading, spacing: 10) {
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(paragraphs[index])
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - BulletRow

private struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\u{2022}")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)
            // Use AttributedString to render inline Markdown (**bold**, `code`)
            if let attributed = try? AttributedString(markdown: text,
                                                      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preview

#Preview("Unseen entries") {
    let sampleBody = """
    **New**
    - Games now play with the ring switch on silent.
    - Starting a game while music is running stops the other app first.

    **Fixed**
    - The heart no longer lights up for every rated game.
    - Leaving a game before it finished loading no longer crashes the app.

    **Known issues**
    - PS1 and PC Engine can still crash when audio resumes after a call.
    """

    let entries = [
        ChangelogEntry(build: 49, version: "1.0", date: "2026-08-22", body: sampleBody),
        ChangelogEntry(build: 48, version: "1.0", date: "2026-08-21", body: "**New**\n- Controller skins for Delta cores.\n\n**Fixed**\n- N64 save states written correctly."),
    ]

    WhatsNewView(entries: entries, markSeenOnDismiss: false)
}
