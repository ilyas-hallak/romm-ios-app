import SwiftUI

struct BIOSSettingsView: View {
    @StateObject private var viewModel: BIOSSettingsViewModel

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        _viewModel = StateObject(wrappedValue: BIOSSettingsViewModel(useCase: factory.makeBIOSSyncUseCase()))
    }

    var body: some View {
        Form {
            if viewModel.isLoading && viewModel.sections.isEmpty {
                ProgressView()
            }
            ForEach(viewModel.sections) { section in
                SwiftUI.Section(header: Text(section.core.displayName)) {
                    if section.statuses.isEmpty {
                        Text("No BIOS requirements configured.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(section.statuses) { status in
                            BIOSRow(status: status) {
                                Task { await viewModel.download(status, in: section.core) }
                            }
                        }
                    }
                }
            }
            if let err = viewModel.errorMessage {
                SwiftUI.Section {
                    Text(err).foregroundStyle(.red)
                }
            }
            SwiftUI.Section(footer: footer) { EmptyView() }
        }
        .navigationTitle("BIOS Files")
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BIOS files are downloaded from the RomM server and stored in Documents/LibretroSystem.")
            Text("PCSX ReARMed can start when at least one regional variant (SCPH-5500/5501/5502) is available.")
        }
        .font(.caption)
    }
}
