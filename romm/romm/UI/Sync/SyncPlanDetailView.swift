import SwiftUI

/// Every change the server planned for this device, one row per save.
///
/// Its own screen because the overview answers "would anything change", and
/// this one answers "what exactly". Putting both on one screen made the counts
/// impossible to find under the list they summarise.
struct SyncPlanDetailView: View {
    let preview: SyncPreview
    /// Resolves a ROM id to a name. Passed in rather than looked up here: the
    /// overview has already resolved every id in this plan.
    let romName: (Int) -> String

    var body: some View {
        List {
            countsSection
            operationsSection
        }
        .navigationTitle("This Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var countsSection: some View {
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

    private var operationsSection: some View {
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

    private func countRow(_ direction: SyncPreviewOperation.Direction, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: direction.icon)
                .foregroundStyle(direction.tint)
                .frame(width: 24)
            // The count is in the label already; repeating it on the right made
            // the row read "Upload 1 save … 1".
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
                Text(romName(operation.romId))
                if let reason = operation.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let updatedAt = operation.serverUpdatedAt {
                // Over two lines, and with the time: which of two saves is newer
                // is the whole question here, and saves synced on the same day
                // are indistinguishable by date alone.
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

#Preview {
    NavigationStack {
        SyncPlanDetailView(
            preview: SyncPreview(
                deviceId: "75018cac-3f2e-4a91-b7d2-19c4e8f0a1bb",
                reportedSaveCount: 4,
                operations: [
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
                    )
                ]
            ),
            romName: { romId in
                [
                    1: "The Legend of Zelda: The Minish Cap",
                    2: "Pokémon Emerald",
                    3: "Metroid Fusion"
                ][romId] ?? "ROM \(romId)"
            }
        )
    }
}
