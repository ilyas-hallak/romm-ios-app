import SwiftUI
import UniformTypeIdentifiers

struct ControllerSkinsSettingsView: View {
    @StateObject private var viewModel: ControllerSkinsSettingsViewModel
    @State private var showingFilePicker = false

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        _viewModel = StateObject(
            wrappedValue: ControllerSkinsSettingsViewModel(
                useCase: factory.makeControllerSkinsUseCase()
            )
        )
    }

    var body: some View {
        Form {
            addSection
            if let err = viewModel.errorMessage {
                SwiftUI.Section {
                    Text(err).foregroundStyle(.red)
                }
            }
            if viewModel.sections.isEmpty {
                emptySection
            } else {
                ForEach(viewModel.sections) { section in
                    skinSection(section)
                }
            }
            SwiftUI.Section(footer: footerText) { EmptyView() }
        }
        .navigationTitle("Controller Skins")
        .task { viewModel.refresh() }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            viewModel.addFromFile(url)
        }
        .sheet(isPresented: $viewModel.showChoicesSheet, onDismiss: viewModel.onChoicesSheetDismissed) {
            SkinChoicesSheet(viewModel: viewModel)
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        SwiftUI.Section("Add a Skin") {
            TextField("Skin URL or catalog page", text: $viewModel.urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .onSubmit {
                    Task { await viewModel.addFromURL() }
                }

            Button {
                Task { await viewModel.addFromURL() }
            } label: {
                HStack {
                    if viewModel.isAdding {
                        ProgressView()
                            .padding(.trailing, 4)
                    }
                    Text(viewModel.isAdding ? "Adding..." : "Add from Link")
                }
            }
            .disabled(viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isAdding)

            Button("Import from Files") {
                showingFilePicker = true
            }
        }
    }

    private var emptySection: some View {
        SwiftUI.Section {
            Text("No custom skins imported yet. Add a link above or use Import from Files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func skinSection(_ section: ControllerSkinsSettingsViewModel.Section) -> some View {
        SwiftUI.Section(header: Text(section.gameType.displayName)) {
            // "Default" row, active when no custom skin is selected.
            Button {
                viewModel.select(nil, for: section.gameType)
            } label: {
                HStack {
                    Text("Default")
                    Spacer()
                    if section.selectedSkin == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(section.skins) { skin in
                Button {
                    viewModel.select(skin, for: section.gameType)
                } label: {
                    HStack {
                        Text(skin.name)
                        Spacer()
                        if section.selectedSkin?.id == skin.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        viewModel.delete(skin)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A skin change takes effect the next time you start a game.")
            Text("Paste a direct .deltaskin link to import a single skin, or paste the URL of a skin catalog page to browse and pick from all the skins it lists.")
            Text("Skins apply only to the native Delta cores: Game Boy / Color, GBA, NES, SNES, N64, Nintendo DS, and Sega Genesis. PlayStation and PC Engine run via libretro with their own touch controls and are not affected.")
            Text("You can also drop .deltaskin files directly into Documents/ControllerSkins via the Files app.")
            Text("Some skin sites block direct downloads. If \"Add from Link\" fails, open the link in Safari, save the file, and use Import from Files.")
        }
        .font(.caption)
    }

    // MARK: - Helpers

    /// `.deltaskin` has no registered type, so it resolves to a dynamic UTI.
    /// `.zip` is allowed alongside it because browsers often save the archive
    /// under that extension.
    private var allowedTypes: [UTType] {
        var types: [UTType] = []
        if let deltaskin = UTType(filenameExtension: "deltaskin") {
            types.append(deltaskin)
        }
        types.append(.zip)
        return types
    }
}
