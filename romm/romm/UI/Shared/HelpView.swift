import SwiftUI
import MarkdownUI

/// The help screen: questions collapsed, answers on tap.
///
/// Reachable from Settings and, more importantly, from the setup screen after a
/// failed sign-in. Most of what users report is a connection problem, and by
/// then they cannot reach Settings at all.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: HelpViewModel

    /// Question to open on appear, matched by prefix so the caller does not have
    /// to repeat the full wording of a headline that may well be edited later.
    private let highlightedQuestion: String?

    init(repository: PHelpRepository = HelpRepository(), highlightedQuestion: String? = nil) {
        _viewModel = State(wrappedValue: HelpViewModel(repository: repository))
        self.highlightedQuestion = highlightedQuestion
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.document.isEmpty {
                    unavailableView
                } else {
                    content
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { await viewModel.load(opening: highlightedQuestion) }
    }

    private var content: some View {
        List {
            ForEach(viewModel.document.sections) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func entryRow(_ entry: HelpEntry) -> some View {
        DisclosureGroup(isExpanded: viewModel.binding(for: entry)) {
            Markdown(entry.answer)
                .markdownTextStyle(\.text) {
                    FontSize(15)
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(entry.question)
                .font(.subheadline)
                .fontWeight(.medium)
                // The question is the tap target, so it has to survive long
                // wording rather than being cut off mid-sentence.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Help unavailable", systemImage: "questionmark.circle")
        } description: {
            Text("The help could not be loaded. Please try again later.")
        }
    }
}

/// A question to open the help on, wrapped so it can drive `.sheet(item:)`.
struct HelpTopic: Identifiable {
    let question: String

    var id: String { question }
}

@Observable
@MainActor
final class HelpViewModel {

    private(set) var document = HelpDocument(sections: [])
    private(set) var isLoading = true
    private var expandedQuestions: Set<String> = []

    private let repository: PHelpRepository

    init(repository: PHelpRepository) {
        self.repository = repository
    }

    func load(opening question: String?) async {
        // Runs again whenever the view reappears; loading twice would flash the
        // spinner over content that is already on screen.
        guard document.isEmpty else { return }
        let markdown = await repository.helpMarkdown()
        document = HelpDocument.parse(markdown)
        isLoading = false
        guard let question else { return }
        expandedQuestions = matches(for: question)
    }

    func binding(for entry: HelpEntry) -> Binding<Bool> {
        Binding(
            get: { self.expandedQuestions.contains(entry.question) },
            set: { isExpanded in
                if isExpanded {
                    self.expandedQuestions.insert(entry.question)
                } else {
                    self.expandedQuestions.remove(entry.question)
                }
            }
        )
    }

    /// Prefix match, case-insensitive: the caller names the beginning of a
    /// question and the exact headline stays free to change.
    private func matches(for prefix: String) -> Set<String> {
        let needle = prefix.lowercased()
        let questions = document.sections
            .flatMap(\.entries)
            .map(\.question)
            .filter { $0.lowercased().hasPrefix(needle) }
        return Set(questions)
    }
}
