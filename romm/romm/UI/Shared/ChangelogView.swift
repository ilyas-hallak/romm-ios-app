import SwiftUI
import MarkdownUI

/// Shows CHANGELOG.md as it is written, newest build first.
///
/// Same screen either way: presented on its own after an update it reads as
/// "what's new", opened from Settings it reads as the version history. Only the
/// framing differs, so there is nothing to parse or filter.
struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

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

    private let markdown: String
    private let mode: Mode
    /// Called when the sheet closes, whichever way. After an update this is what
    /// marks the changelog as seen.
    private let onClose: () -> Void

    init(markdown: String, mode: Mode, onClose: @escaping () -> Void = {}) {
        self.markdown = markdown
        self.mode = mode
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Markdown(markdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
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

#Preview("What's New") {
    ChangelogView(markdown: """
    # Changelog

    ## Version 1.0

    ### Build 49 (2026-08-22)

    **New**
    - Games now play with the ring switch on silent.

    **Fixed**
    - The heart no longer lights up for every rated game.
    """, mode: .whatsNew)
}
