import SwiftUI

/// Shows what syncing saves would do, without doing any of it.
///
/// Grouped by source rather than by game, because the question this screen
/// answers is "where do my saves live and do those places agree", which a list
/// of games cannot show. Only two sources exist so far, this device and the
/// server; external emulator apps are meant to join them as further rows.
struct SyncOverviewView: View {
    @State private var viewModel = SyncOverviewViewModel()

    var body: some View {
        Form {
            switch viewModel.state {
            case .idle, .loading:
                loadingSection
            case .failed(let error):
                failureSection(error)
            case .loaded(let preview):
                sourcesSection(preview)
                plannedSection(preview)
                if !preview.isUpToDate {
                    operationsSection(preview)
                }
            }
        }
        .navigationTitle("Save Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    // MARK: - Sections

    private var loadingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Asking the server what would change…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failureSection(_ error: SyncPreviewError) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error.localizedDescription)
            }
        } header: {
            Text("Not Available")
        }
    }

    private func sourcesSection(_ preview: SyncPreview) -> some View {
        Section {
            sourceRow(
                icon: "iphone",
                title: String(localized: "This Device"),
                detail: preview.reportedSaveCount == 1
                    ? String(localized: "1 battery save")
                    : String(localized: "\(preview.reportedSaveCount) battery saves")
            )
            sourceRow(
                icon: "server.rack",
                title: String(localized: "RomM Server"),
                detail: String(localized: "Connected")
            )
        } header: {
            Text("Sources")
        } footer: {
            Text("Registered as device \(preview.deviceId).")
                .font(.caption2)
        }
    }

    private func sourceRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func plannedSection(_ preview: SyncPreview) -> some View {
        Section {
            if preview.isUpToDate {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Everything is up to date.")
                }
            } else {
                countRow(.upload, count: preview.uploads.count)
                countRow(.download, count: preview.downloads.count)
                if !preview.conflicts.isEmpty {
                    countRow(.conflict, count: preview.conflicts.count)
                }
            }
        } header: {
            Text("A Sync Would")
        } footer: {
            // Said plainly because the screen otherwise reads like it is syncing,
            // and because uploads still send no slot, so this is a preview of a
            // change that has not been made yet.
            Text("Nothing has been changed. This is what a sync would do once "
                + "saves are uploaded under a slot.")
        }
    }

    private func countRow(_ direction: SyncPreviewOperation.Direction, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: direction.icon)
                .foregroundStyle(direction.tint)
                .frame(width: 24)
            Text(direction.summary(count: count))
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func operationsSection(_ preview: SyncPreview) -> some View {
        Section {
            // Conflicts first: they are the only rows that cannot be resolved by
            // letting the sync run, so they must not be buried under the rest.
            ForEach(preview.conflicts + preview.uploads + preview.downloads) { operation in
                operationRow(operation)
            }
        } header: {
            Text("Changes")
        }
    }

    private func operationRow(_ operation: SyncPreviewOperation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: operation.direction.icon)
                .foregroundStyle(operation.direction.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayName(forRom: operation.romId))
                if let reason = operation.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let updatedAt = operation.serverUpdatedAt {
                Text(updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension SyncPreviewOperation.Direction {
    var icon: String {
        switch self {
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .noOp: return "equal.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .upload: return .blue
        case .download: return .green
        case .conflict: return .orange
        case .noOp: return .secondary
        }
    }

    func summary(count: Int) -> String {
        switch self {
        case .upload:
            return count == 1
                ? String(localized: "Upload 1 save")
                : String(localized: "Upload \(count) saves")
        case .download:
            return count == 1
                ? String(localized: "Download 1 save")
                : String(localized: "Download \(count) saves")
        case .conflict:
            return count == 1
                ? String(localized: "1 conflict to resolve")
                : String(localized: "\(count) conflicts to resolve")
        case .noOp:
            return String(localized: "Already in sync")
        }
    }
}
