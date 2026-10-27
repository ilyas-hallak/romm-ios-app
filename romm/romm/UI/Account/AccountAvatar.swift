import SwiftUI

/// The signed in user as a circle: their avatar when the server has one, their
/// initials on a tinted disc when it has not.
struct AccountAvatar: View {
    let urlString: String?
    let username: String
    var size: CGFloat = 30

    var body: some View {
        CachedKFImage(urlString: urlString) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            initialsDisc
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsDisc: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(initials)
                    // Scaled off the disc so the same view works as a 30pt
                    // toolbar button and as the header of the account sheet.
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    /// Up to two letters, taken from the parts of the name. Falls back to a
    /// person glyph's stand-in for a name that carries no letter at all.
    private var initials: String {
        let letters = username
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" })
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

#Preview("With initials") {
    VStack(spacing: 16) {
        AccountAvatar(urlString: nil, username: "ilyas", size: 30)
        AccountAvatar(urlString: nil, username: "ilyas.hallak", size: 64)
        AccountAvatar(urlString: nil, username: "", size: 64)
    }
    .padding()
}
