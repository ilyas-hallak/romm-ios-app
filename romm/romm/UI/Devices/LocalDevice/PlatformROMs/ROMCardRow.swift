import SwiftUI

struct ROMCardRow: View {
    let rom: DownloadedROM
    let isPlayable: Bool
    let isLaunching: Bool
    let isDisabled: Bool
    let hasSaveGame: Bool
    let hasSaveState: Bool
    let onPlay: () -> Void
    let onSync: () -> Void
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CachedKFImage(urlString: rom.urlCover) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(rom.platformSlug)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                        .background(Color(.secondarySystemGroupedBackground))
                }
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(rom.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(rom.formattedSize)
                        Text("•")
                        Text(rom.formattedDate)
                        if rom.files.count > 1 {
                            Text("•")
                            Text("\(rom.files.count) files")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                    if hasSaveGame || hasSaveState {
                        HStack(spacing: 6) {
                            if hasSaveGame {
                                SaveBadge(icon: "memorychip", title: "Save game", tint: .blue)
                            }
                            if hasSaveState {
                                SaveBadge(icon: "bookmark.fill", title: "Save state", tint: .purple)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if isLaunching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                        Text("Launching")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color.green.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    CardActionButton(
                        title: "Play",
                        systemImage: "play.fill",
                        tint: .green,
                        filled: true,
                        action: onPlay
                    )
                    .disabled(!isPlayable || isDisabled)
                    .opacity((!isPlayable || isDisabled) ? 0.5 : 1)
                }

                Button(action: onDetails) {
                    CardActionLabel(title: "Details", systemImage: "info.circle", tint: .accentColor)
                }
                .buttonStyle(.plain)

                CardActionButton(
                    title: "Sync",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .accentColor,
                    filled: false,
                    action: onSync
                )
            }
        }
        .padding(.vertical, 4)
        .opacity(isLaunching ? 0.7 : 1)
    }
}

struct SaveBadge: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

struct CardActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardActionLabel(title: title, systemImage: systemImage, tint: filled ? .white : tint, filled: filled, fillColor: tint)
        }
        .buttonStyle(.plain)
    }
}

struct CardActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    var filled: Bool = false
    var fillColor: Color = .clear

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(filled ? fillColor : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(filled ? Color.clear : tint.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
