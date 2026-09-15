import SwiftUI

/// What was found in one emulator app's save folder.
///
/// Files rather than a plan: these saves are read but not yet negotiated, so
/// there is no direction to show. What is there and how old it is is what makes
/// a wrong folder recognisable.
struct ExternalScanDetailView: View {
    let scan: ExternalSaveScan
    let romName: (Int) -> String

    var body: some View {
        List {
            if !scan.matched.isEmpty {
                matchedSection
            }
            if !scan.unmatchedFileNames.isEmpty {
                unmatchedSection
            }
        }
        .navigationTitle(scan.emulator.emulator.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var matchedSection: some View {
        Section {
            ForEach(scan.matched) { save in
                matchedRow(save)
            }
        } header: {
            Text("Saves For Your Games")
        } footer: {
            Text("These will be part of the sync plan once syncing writes to "
                + "emulator apps. Nothing is uploaded or changed yet.")
        }
    }

    private func matchedRow(_ save: ExternalSaveFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(romName(save.romId))
            HStack(spacing: 6) {
                Text(save.modifiedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                Text("·")
                Text(save.sizeBytes.formatted(.byteCount(style: .file)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Last and truncated: it identifies the save in the app's folder
            // but must not push the game's name around.
            Text(save.fileName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var unmatchedSection: some View {
        Section {
            ForEach(scan.unmatchedFileNames, id: \.self) { fileName in
                Text(fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } header: {
            Text("Not Recognised")
        } footer: {
            // Named rather than hidden: a missing game is a different problem
            // from an empty folder.
            Text("Saves whose game is not on this device. Download the game in "
                + "RomM and they will be matched.")
        }
    }
}

#Preview {
    let candidate = { (name: String, days: Double, size: Int) in
        ExternalSaveCandidate(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileName: name,
            sizeBytes: size,
            modifiedAt: Date(timeIntervalSince1970: 1_788_000_000 - days * 86_400)
        )
    }
    return NavigationStack {
        ExternalScanDetailView(
            scan: ExternalSaveScan(
                emulator: .delta,
                matched: [
                    ExternalSaveFile(candidate: candidate("Pokemon Emerald.sav", 1, 131_072), romId: 2),
                    ExternalSaveFile(candidate: candidate("Metroid Fusion.sav", 12, 65_536), romId: 3)
                ],
                unmatchedFileNames: ["Advance Wars.sav", "Fire Emblem.sav"],
                isStale: false
            ),
            romName: { romId in
                [2: "Pokémon Emerald", 3: "Metroid Fusion"][romId] ?? "ROM \(romId)"
            }
        )
    }
}
