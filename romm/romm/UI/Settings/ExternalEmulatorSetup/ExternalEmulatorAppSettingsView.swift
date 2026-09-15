import SwiftUI

/// Settings for one emulator app that has been set up: its save folder, and
/// removing it again.
struct ExternalEmulatorAppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ExternalEmulatorAppSettingsViewModel
    @State private var isPickingFolder = false
    @State private var isConfirmingRemoval = false

    /// Called after the app was removed, so the list behind this screen refreshes.
    let onRemoved: () -> Void

    init(emulator: ExternalEmulatorID, onRemoved: @escaping () -> Void) {
        _viewModel = State(initialValue: ExternalEmulatorAppSettingsViewModel(emulator: emulator))
        self.onRemoved = onRemoved
    }

    var body: some View {
        Form {
            statusSection
            if viewModel.supportsSaveReading {
                saveFolderSection
            }
            removeSection
        }
        .navigationTitle(viewModel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refresh() }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { viewModel.grantFolder(url) }
        }
        .confirmationDialog(
            "Remove \(viewModel.displayName)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                viewModel.removeApp()
                onRemoved()
                dismiss()
            }
        } message: {
            Text("The app and its games stay on your device. Only this setup is forgotten, "
                + "including access to its save folder.")
        }
        .alert(
            "Folder",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Installed") {
                Text(viewModel.isInstalled ? "Yes" : "No")
                    .foregroundStyle(viewModel.isInstalled ? .secondary : Color.orange)
            }
            if viewModel.isPlayTarget {
                Label("Play opens games here", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var saveFolderSection: some View {
        Section {
            if let scan = viewModel.scan {
                LabeledContent("Saves") {
                    Text(scan.statusSummary)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(scan.matched.isEmpty ? Color.orange : .secondary)
                }
                Button("Choose a Different Folder…") { isPickingFolder = true }
                Button("Disconnect Folder", role: .destructive) { viewModel.revokeFolder() }
            } else {
                Button("Choose Folder…") { isPickingFolder = true }
            }
        } header: {
            Text("Saves")
        } footer: {
            Text(viewModel.hasFolder
                 ? String(localized: "Saves made in \(viewModel.displayName) are read from this folder. Nothing is written to it.")
                 : String(localized: "Pick \(viewModel.displayName)'s folder in Files so its saves can be read. Nothing is written to it."))
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove \(viewModel.displayName)", role: .destructive) {
                isConfirmingRemoval = true
            }
        }
    }
}
