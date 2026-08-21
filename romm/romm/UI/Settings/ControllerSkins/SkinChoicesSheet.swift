import SwiftUI

/// Sheet that lists all skins found on a catalog page and lets the user
/// import one or more of them individually.
struct SkinChoicesSheet: View {
    @ObservedObject var viewModel: ControllerSkinsSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.skinChoices) { link in
                SkinChoiceRow(link: link, state: viewModel.skinImportStates[link.url] ?? .ready) {
                    Task { await viewModel.importLink(link) }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                sheetFooter
            }
        }
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        let count = viewModel.skinChoices.count
        return count == 1 ? "1 Skin Found" : "\(count) Skins Found"
    }

    private var sheetFooter: some View {
        Text("Imported skins are not activated automatically. Select the one you want on the main screen after closing this sheet.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
    }
}

// MARK: - Row

private struct SkinChoiceRow: View {
    let link: ControllerSkinLink
    let state: SkinLinkImportState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Fixed-width leading slot so the name never shifts when the
                // spinner appears.
                ZStack {
                    switch state {
                    case .ready:
                        EmptyView()
                    case .loading:
                        ProgressView()
                    case .imported:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(link.name)
                        .foregroundStyle(isDisabled ? .secondary : .primary)

                    if case .failed(let message) = state {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var isDisabled: Bool {
        switch state {
        case .loading, .imported: return true
        case .ready, .failed: return false
        }
    }
}
