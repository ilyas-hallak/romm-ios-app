import SwiftUI

/// Where a row leads once the sheet is out of the way. Home owns the stack, so
/// the push happens there and not from inside a sheet that is closing.
enum AccountDestination: Hashable {
    case saveSync
    case settings
    case statistics
}

/// The account behind the avatar on Home, the way the web app hangs its
/// settings off the signed in user.
///
/// Everything about the account lives here: who is signed in, which server,
/// how saves last synced, and the way out. Settings itself stays a screen of
/// its own and is reached from here.
struct AccountSheet: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) private var dismiss

    let avatarURLString: String?
    let syncStatus: SaveSyncStatus
    let onSelect: (AccountDestination) -> Void

    @State private var profileViewModel = ProfileViewModel()
    @State private var showingHelp = false
    @State private var showingLogoutAlert = false
    @State private var showingResetAlert = false

    var body: some View {
        NavigationStack {
            List {
                header
                #if !APP_STORE
                saveSyncSection
                #endif
                settingsSection
                accountSection
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
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .alert("Logout", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Logout", role: .destructive) {
                profileViewModel.logout()
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .alert("Reset Configuration", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                profileViewModel.restartSetup()
            }
        } message: {
            Text("This will delete all configuration settings including your server connection and credentials. You will be returned to the setup screen.")
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

            Button {
                select(.statistics)
            } label: {
                row(icon: "chart.bar", title: String(localized: "Server Statistics"))
            }

            Button {
                showingHelp = true
            } label: {
                row(icon: "questionmark.circle", title: String(localized: "Help"))
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                showingLogoutAlert = true
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            }

            if appData.currentConfiguration != nil {
                Button {
                    showingResetAlert = true
                } label: {
                    Label("Reset Configuration", systemImage: "arrow.clockwise")
                        .foregroundStyle(.orange)
                }
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

#Preview("Pending sync") {
    Text("Home")
        .sheet(isPresented: .constant(true)) {
            AccountSheet(
                avatarURLString: nil,
                syncStatus: .pending(summary: "2 up, 1 down"),
                onSelect: { _ in }
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
                onSelect: { _ in }
            )
            .environmentObject(AppData())
        }
}
