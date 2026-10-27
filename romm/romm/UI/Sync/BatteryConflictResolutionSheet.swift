import SwiftUI

/// Lets the user pick a winner for a battery save conflict: both sides changed
/// since the last sync, and neither can be preferred automatically. Whatever
/// is discarded is backed up locally first, see `BatteryConflictResolver`.
struct BatteryConflictResolutionSheet: View {
    @State var viewModel: BatteryConflictViewModel
    let romName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.state {
                case .loading:
                    loadingSection
                case .failed(let message):
                    failureSection(message)
                case .ready(let local, let server):
                    sideSection(title: String(localized: "This Device"), icon: "iphone", side: local)
                    sideSection(title: String(localized: "Server"), icon: "cloud", side: server)
                    actionsSection
                }
            }
            .navigationTitle(romName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isResolving)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private func sideSection(title: String, icon: String, side: BatteryConflictViewModel.Side) -> some View {
        Section {
            sideRow(icon: icon, side: side)
        } header: {
            Text(title)
        }
    }

    private func sideRow(icon: String, side: BatteryConflictViewModel.Side) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            sideDateAndDevice(side)
            Spacer()
            sideSize(side)
        }
    }

    @ViewBuilder
    private func sideDateAndDevice(_ side: BatteryConflictViewModel.Side) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            sideDate(side)
            if let deviceName = side.deviceName {
                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sideDate(_ side: BatteryConflictViewModel.Side) -> some View {
        if let date = side.date {
            Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
        } else {
            Text("Unknown date")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sideSize(_ side: BatteryConflictViewModel.Side) -> some View {
        if let sizeBytes = side.sizeBytes {
            Text(sizeBytes.formatted(.byteCount(style: .file)))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    await viewModel.keepThisDevice()
                    dismissIfResolved()
                }
            } label: {
                resolveLabel("Keep This Device")
            }
            .disabled(viewModel.isResolving)

            Button {
                Task {
                    await viewModel.keepServer()
                    dismissIfResolved()
                }
            } label: {
                resolveLabel("Keep Server")
            }
            .disabled(viewModel.isResolving)
        } footer: {
            Text("The version you don't keep is backed up on this device first, so nothing is lost.")
        }
    }

    private func resolveLabel(_ title: LocalizedStringKey) -> some View {
        HStack {
            Spacer()
            if viewModel.isResolving {
                ProgressView().padding(.trailing, 8)
            }
            Text(title)
            Spacer()
        }
    }

    private func dismissIfResolved() {
        guard viewModel.errorMessage == nil else { return }
        dismiss()
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading both versions…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
            }
        }
    }
}
