import SwiftUI
import UIKit

/// Shown before launching a ROM that already has save states. Lets the player
/// continue from the most recent snapshot, pick a specific slot, or start a
/// fresh session. When a ROM has no save states the caller skips this sheet and
/// launches directly, so the sheet always has at least one entry to show.
struct PreLaunchSheet: View {
    let romName: String
    let romId: Int
    let saveStore: PSaveStore
    /// Called with the slot to resume from, or `nil` to start without loading a
    /// save state. The caller is responsible for dismissing the sheet.
    let onLaunch: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var states: [SaveStateEntry] {
        let list = (try? saveStore.listStates(romId: romId)) ?? []
        return list.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let newest = states.first {
                        continueCard(for: newest)
                    }

                    newGameButton

                    if states.count > 1 {
                        otherStatesSection
                    }
                }
                .padding(16)
            }
            .navigationTitle(romName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Continue (most recent state)

    private func continueCard(for entry: SaveStateEntry) -> some View {
        Button {
            onLaunch(entry.slot)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                thumbnail(for: entry.slot)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue")
                            .font(.headline)
                        Text("Slot \(entry.slot) • \(entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.title3)
                }
                .foregroundColor(.primary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - New game

    private var newGameButton: some View {
        Button {
            onLaunch(nil)
        } label: {
            HStack {
                Image(systemName: "gamecontroller")
                Text("New Game")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Other save states

    private var otherStatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other Save States")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(states.dropFirst()) { entry in
                Button {
                    onLaunch(entry.slot)
                } label: {
                    HStack(spacing: 12) {
                        thumbnail(for: entry.slot)
                            .frame(width: 64, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Slot \(entry.slot)")
                                .font(.subheadline.weight(.medium))
                            Text(entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func thumbnail(for slot: Int) -> some View {
        if let data = try? saveStore.readThumbnail(romId: romId, slot: slot),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(Color(.tertiarySystemBackground))
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
    }
}
