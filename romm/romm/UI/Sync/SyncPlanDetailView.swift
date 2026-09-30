import SwiftUI

/// Every change the server planned for this device, one row per save, and the
/// means to carry the plan out.
///
/// Its own screen because the overview answers "would anything change" and
/// this one answers "what exactly", and now "did it work".
struct SyncPlanDetailView: View {
    /// A `let` to an `@Observable` class still tracks its properties: the view
    /// only needs one source of truth for the plan and the apply it drives.
    let viewModel: SyncOverviewViewModel

    var body: some View {
        List {
            if let preview = viewModel.preview {
                countsSection(preview)
                conflictsSection(preview)
                changesSection(preview)
                applySection
                if let report = viewModel.applyReport {
                    reportSection(report)
                    Section {
                        Button("Check Again") {
                            Task { await viewModel.reload() }
                        }
                    } footer: {
                        Text("Syncing again will ask the server what changed from here.")
                    }
                }
            }
        }
        .navigationTitle("This Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countsSection(_ preview: SyncPreview) -> some View {
        Section {
            if !preview.uploads.isEmpty {
                countRow(.upload, count: preview.uploads.count)
            }
            if !preview.downloads.isEmpty {
                countRow(.download, count: preview.downloads.count)
            }
            if !preview.conflicts.isEmpty {
                countRow(.conflict, count: preview.conflicts.count)
            }
        } header: {
            Text("A Sync Would")
        }
    }

    // MARK: - Conflicts

    @ViewBuilder
    private func conflictsSection(_ preview: SyncPreview) -> some View {
        if !preview.conflicts.isEmpty {
            Section {
                ForEach(preview.conflicts) { operation in
                    conflictRow(operation)
                }
            } header: {
                Text("Conflicts")
            } footer: {
                Text("Both sides changed since the last sync, so you decide which save "
                    + "survives. Anything left undecided stays untouched.")
            }
        }
    }

    private func conflictRow(_ operation: SyncPreviewOperation) -> some View {
        let resolution = viewModel.resolution(for: operation)
        let isLocked = viewModel.isApplying || viewModel.applyReport != nil

        return HStack(alignment: .top, spacing: 12) {
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
            Menu {
                ForEach(SyncConflictResolution.allCases, id: \.self) { choice in
                    Button {
                        viewModel.resolve(operation, as: choice)
                    } label: {
                        Label(choice.label, systemImage: choice.icon)
                    }
                }
            } label: {
                Text(resolution?.shortLabel ?? String(localized: "Decide"))
                    .font(.callout)
                    .foregroundStyle(resolution == nil ? Color.orange : .secondary)
            }
            .disabled(isLocked)
        }
    }

    // MARK: - Changes

    @ViewBuilder
    private func changesSection(_ preview: SyncPreview) -> some View {
        if !preview.uploads.isEmpty || !preview.downloads.isEmpty {
            Section {
                ForEach(preview.uploads + preview.downloads) { operation in
                    operationRow(operation)
                }
            } header: {
                Text("Changes")
            }
        }
    }

    // MARK: - Apply

    @ViewBuilder
    private var applySection: some View {
        switch viewModel.applyState {
        case .idle:
            Section {
                Button("Sync Now") {
                    Task { await viewModel.apply() }
                }
                .disabled(!viewModel.canApply)
            } footer: {
                if viewModel.unresolvedConflictCount > 0 {
                    Text(viewModel.unresolvedConflictCount == 1
                        ? String(localized: "1 conflict has no decision yet and will be left alone.")
                        : String(localized: "\(viewModel.unresolvedConflictCount) conflicts have no decision yet and will be left alone."))
                } else {
                    Text("Saves are uploaded and downloaded as listed above. A save "
                        + "replaced in another app's folder is kept as a backup.")
                }
            }
        case .running(let completed, let total):
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    // As text, since interpolating an Int formats it for the
                    // locale and groups the thousands of a large library.
                    Text("Syncing \(String(completed)) of \(String(total))…")
                        .foregroundStyle(.secondary)
                }
            }
        case .finished:
            EmptyView()
        }
    }

    // MARK: - Report

    private func reportSection(_ report: SyncApplyReport) -> some View {
        Section {
            Text(reportSummary(report))
            ForEach(report.outcomes.filter { $0.status != .applied }) { outcome in
                outcomeRow(outcome)
            }
            if !report.sessionClosed {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text("The saves were synced, but the server was not told the sync finished.")
                }
            }
        } header: {
            Text("Result")
        }
    }

    private func reportSummary(_ report: SyncApplyReport) -> String {
        var parts: [String] = [
            report.applied.count == 1
                ? String(localized: "1 save synced")
                : String(localized: "\(report.applied.count) saves synced")
        ]
        if !report.skips.isEmpty {
            parts.append(
                report.skips.count == 1
                    ? String(localized: "1 left alone")
                    : String(localized: "\(report.skips.count) left alone")
            )
        }
        if !report.failures.isEmpty {
            parts.append(
                report.failures.count == 1
                    ? String(localized: "1 failed")
                    : String(localized: "\(report.failures.count) failed")
            )
        }
        return parts.joined(separator: ", ")
    }

    private func outcomeRow(_ outcome: SyncApplyOutcome) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: outcome.status.icon)
                .foregroundStyle(outcome.status.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayName(forRom: outcome.operation.romId))
                switch outcome.status {
                case .skipped(let reason):
                    Text(reason.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .applied:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Shared rows

    private func countRow(_ direction: SyncPreviewOperation.Direction, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: direction.icon)
                .foregroundStyle(direction.tint)
                .frame(width: 24)
            // The count is in the label, so no trailing value.
            Text(direction.summary(count: count))
            Spacer()
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
                // With the time, since saves synced on the same day are
                // indistinguishable by date alone.
                VStack(alignment: .trailing, spacing: 1) {
                    Text(updatedAt, format: .dateTime.day().month(.abbreviated).year())
                    Text(updatedAt, format: .dateTime.hour().minute())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
        }
    }
}

// MARK: - Previews

private let previewOperations = [
    SyncPreviewOperation(
        romId: 1,
        direction: .upload,
        serverFileName: nil,
        slot: SaveSlot.battery,
        emulator: nil,
        reason: "Save exists on client but not on server",
        serverUpdatedAt: nil
    ),
    SyncPreviewOperation(
        romId: 2,
        direction: .download,
        serverFileName: "Pokemon [2026-09-04_22-01-15].sav",
        slot: SaveSlot.battery,
        emulator: nil,
        reason: "Server save is newer (no sync history)",
        serverUpdatedAt: Date(timeIntervalSince1970: 1_788_000_000)
    ),
    SyncPreviewOperation(
        romId: 3,
        direction: .conflict,
        serverFileName: "Metroid [2026-09-04_22-01-15].sav",
        slot: SaveSlot.battery,
        emulator: nil,
        reason: "Both changed since the last sync",
        serverUpdatedAt: Date(timeIntervalSince1970: 1_788_000_000)
    ),
    SyncPreviewOperation(
        romId: 4,
        direction: .upload,
        serverFileName: nil,
        slot: SaveSlot.battery(for: .delta),
        emulator: ExternalEmulatorID.delta.rawValue,
        reason: "Save exists in Delta but not on server",
        serverUpdatedAt: nil
    )
]

private let previewPlan = SyncPreview(
    deviceId: "75018cac-3f2e-4a91-b7d2-19c4e8f0a1bb",
    sessionId: 42,
    reportedSaveCount: 4,
    reportedCountsBySource: [.internalStore: 3, .externalApp(.delta): 1],
    operations: previewOperations
)

private let previewNames = [
    1: "The Legend of Zelda: The Minish Cap",
    2: "Pokémon Emerald",
    3: "Metroid Fusion",
    4: "Chrono Trigger"
]

#Preview("Plan to apply") {
    NavigationStack {
        SyncPlanDetailView(viewModel: SyncOverviewViewModel(
            showing: .loaded(previewPlan),
            romNames: previewNames
        ))
    }
}

/// The report, with one of each outcome and a session the server never
/// acknowledged: the crowded case is the one worth looking at.
#Preview("Applied") {
    NavigationStack {
        SyncPlanDetailView(viewModel: SyncOverviewViewModel(
            showing: .loaded(previewPlan),
            applyState: .finished(SyncApplyReport(
                outcomes: [
                    SyncApplyOutcome(operation: previewOperations[0], status: .applied),
                    SyncApplyOutcome(operation: previewOperations[1], status: .applied),
                    SyncApplyOutcome(operation: previewOperations[2], status: .skipped(.conflictSkipped)),
                    SyncApplyOutcome(
                        operation: previewOperations[3],
                        status: .failed("The server refused the upload.")
                    )
                ],
                sessionClosed: false
            )),
            resolutions: [previewOperations[2].id: .skip],
            romNames: previewNames
        ))
    }
}
