import SwiftUI

/// The account in the corner of Home, the way the web app has it: the avatar,
/// with a small badge for how the last save sync went.
struct AccountButton: View {
    let username: String
    let avatarURLString: String?
    let syncStatus: SaveSyncStatus
    let action: () -> Void

    private let size: CGFloat = 30

    var body: some View {
        Button(action: action) {
            AccountAvatar(urlString: avatarURLString, username: username, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if let icon = syncStatus.badgeIcon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            // Two layers so the badge keeps its shape on a busy
                            // avatar instead of blending into it.
                            .foregroundStyle(syncStatus.tint, Color(.systemBackground))
                            .offset(x: 3, y: 3)
                    }
                }
        }
        .accessibilityLabel("Account")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        syncStatus.badgeIcon == nil
            ? username
            : "\(username), \(syncStatus.accessibilityDescription)"
    }
}

#Preview {
    NavigationStack {
        Text("Home")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    AccountButton(
                        username: "ilyas",
                        avatarURLString: nil,
                        syncStatus: .pending(summary: "2 up, 1 down"),
                        action: {}
                    )
                }
            }
    }
}
