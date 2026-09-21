import SwiftUI

/// Where a row leads once the sheet is out of the way. Home owns the stack, so
/// the push happens there and not from inside a sheet that is closing.
enum AccountDestination: Hashable {
    case saveSync
    case settings
    case statistics
    case retroAchievements
}

/// The account behind the avatar on Home, the way the web app hangs its
/// settings off the signed in user.
///
/// Holds what a user reaches for often: who is signed in, how saves last
/// synced, what the server knows, and the two pages about the app itself.
/// Everything else, signing out included, lives behind Settings.
struct AccountSheet: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) private var dismiss

    let avatarURLString: String?
    let syncStatus: SaveSyncStatus
    let canCheckSync: Bool
    let isChecking: Bool
    let changelog: String
    let onSelect: (AccountDestination) -> Void
    let onCheckSync: () -> Void

    @State private var showingHelp = false
    @State private var showingVersionHistory = false

    var body: some View {
        NavigationStack {
            List {
                header
                #if !APP_STORE
                saveSyncSection
                #endif
                settingsSection
                serverSection
                aboutSection
            }
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // The list itself draws no background inside a sheet, so without this
        // the whole of Home blurs through the system's glass surface, hardest
        // while the sheet is still on its way up. This is a page of settings,
        // not a floating control, so it gets a solid one.
        .presentationBackground(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $showingVersionHistory) {
            // The whole history, and no mark-seen side effect.
            ChangelogView(markdown: changelog, mode: .versionHistory)
        }
    }

    // MARK: - Header

    private var header: some View {
        Section {
            HStack(spacing: 16) {
                AccountAvatar(urlString: avatarURLString, username: appData.displayUsername, size: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appData.displayUsername)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let role = appData.currentUser?.role {
                        Text(role.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let server = appData.currentConfiguration?.serverURL {
                        Label(server, systemImage: "server.rack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .listRowBackground(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    // MARK: - Sections

    private var saveSyncSection: some View {
        Section {
            Button {
                select(.saveSync)
            } label: {
                row(icon: "arrow.triangle.2.circlepath", title: String(localized: "Save Sync")) {
                    HStack(spacing: 6) {
                        if case .checking = syncStatus {
                            ProgressView()
                                .controlSize(.small)
                        } else if let icon = syncStatus.badgeIcon {
                            Image(systemName: icon)
                                .foregroundStyle(syncStatus.tint)
                        }
                        Text(syncStatus.detail)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // The one way to go and ask, see AccountViewModel.checkNow().
            if canCheckSync {
                Button(action: onCheckSync) {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
                .disabled(isChecking)
            }
        } footer: {
            if let explanation = syncStatus.explanation {
                Text(explanation)
            }
        }
    }

    private var settingsSection: some View {
        Section {
            Button {
                select(.settings)
            } label: {
                row(icon: "gearshape", title: String(localized: "Settings"))
            }
        }
    }

    /// What the server knows, as opposed to what the app is set to.
    private var serverSection: some View {
        Section {
            Button {
                select(.statistics)
            } label: {
                row(icon: "chart.bar", title: String(localized: "Server Statistics"))
            }

            Button {
                select(.retroAchievements)
            } label: {
                row(icon: "trophy", title: String(localized: "RetroAchievements")) {
                    Text(appData.currentUser?.linkedRetroAchievementsUsername
                        ?? String(localized: "Not linked"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The two pages about the app itself.
    private var aboutSection: some View {
        Section {
            Button {
                showingHelp = true
            } label: {
                row(icon: "questionmark.circle", title: String(localized: "Help"))
            }

            Button {
                showingVersionHistory = true
            } label: {
                row(icon: "clock.arrow.circlepath", title: String(localized: "Version History"))
            }
        }
    }

    // MARK: - Rows

    /// A row that reads like a `NavigationLink` but only reports the choice:
    /// the push belongs to Home, see `AccountDestination`.
    private func row<Trailing: View>(
        icon: String,
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            trailing()
                .font(.callout)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func select(_ destination: AccountDestination) {
        onSelect(destination)
        dismiss()
    }
}

#Preview("Nothing checked yet") {
    Text("Home")
        .sheet(isPresented: .constant(true)) {
            AccountSheet(
                avatarURLString: nil,
                syncStatus: .unknown,
                canCheckSync: true,
                isChecking: false,
                changelog: "# 1.0.0\n- Erster Eintrag",
                onSelect: { _ in },
                onCheckSync: {}
            )
            .environmentObject(AppData())
        }
}

#Preview("Pending sync") {
    Text("Home")
        .sheet(isPresented: .constant(true)) {
            AccountSheet(
                avatarURLString: nil,
                syncStatus: .pending(summary: "2 up, 1 down"),
                canCheckSync: true,
                isChecking: false,
                changelog: "# 1.0.0\n- Erster Eintrag",
                onSelect: { _ in },
                onCheckSync: {}
            )
            .environmentObject(AppData())
        }
}

#Preview("Server too old") {
    Text("Home")
        .sheet(isPresented: .constant(true)) {
            AccountSheet(
                avatarURLString: nil,
                syncStatus: SaveSyncStatus(error: .serverTooOld(version: "4.8.1")),
                canCheckSync: true,
                isChecking: false,
                changelog: "# 1.0.0\n- Erster Eintrag",
                onSelect: { _ in },
                onCheckSync: {}
            )
            .environmentObject(AppData())
        }
}
