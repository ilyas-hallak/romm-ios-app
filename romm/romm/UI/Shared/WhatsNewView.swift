//
//  WhatsNewView.swift
//  romm
//
//  Created by Ilyas Hallak on 23.08.25.
//

import SwiftUI
import MarkdownUI

// MARK: - WhatsNewView

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    /// Presented automatically after an update it is a "what's new" note; opened
    /// by hand from Settings it is the full history, so the framing differs.
    enum Mode {
        case whatsNew
        case versionHistory

        var title: LocalizedStringKey {
            self == .whatsNew ? "What's New" : "Version History"
        }

        var closeLabel: LocalizedStringKey {
            self == .whatsNew ? "Continue" : "Done"
        }
    }

    private let entries: [ChangelogEntry]
    private let mode: Mode
    /// Called when the sheet closes, whichever way. In What's New mode this is
    /// what marks the entries as seen.
    private let onClose: () -> Void

    init(entries: [ChangelogEntry], mode: Mode, onClose: @escaping () -> Void = {}) {
        self.entries = entries
        self.mode = mode
        self.onClose = onClose
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
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.large)
            // Without an explicit bar background the collapsed title has no
            // backdrop and the scrolling text runs straight through it.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.closeLabel) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onDisappear(perform: onClose)
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

            // The body is authored as plain Markdown, so it is rendered as such.
            // Anything the changelog picks up later (headings, nested lists, code)
            // works without the view having to learn about it.
            Markdown(entry.body)
                .markdownTextStyle(\.text) {
                    ForegroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview("What's New") {
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

    return WhatsNewView(entries: entries, mode: .whatsNew)
}
