import SwiftUI

struct DownloadConfirmSheet: View {
    let rom: Rom
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var formattedSize: String? {
        guard let bytes = rom.sizeBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            CachedKFImage(urlString: rom.urlCover) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.7))
                    )
            }
            .frame(width: 96, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)

            VStack(spacing: 6) {
                Text("Download this game?")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text(rom.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let size = formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 24)

            Text("This game is not on your device yet. Download it now to play.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                }

                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}
