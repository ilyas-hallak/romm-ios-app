//
//  RetroAchievementsSettingsView.swift
//  romm
//
//  Created by Ilyas Hallak on 31.08.26.
//

import SwiftUI
import os

/// Detail screen behind the RetroAchievements row in Settings: which account is
/// linked, what the server knows about its progress, and a way to pull that
/// progress again without restarting the app.
struct RetroAchievementsSettingsView: View {
    private let logger = Logger.ui
    @EnvironmentObject var appData: AppData

    private let refreshUseCase: RefreshRetroAchievementsUseCase
    private let setUsernameUseCase: SetRetroAchievementsUsernameUseCase

    /// Set after a successful refresh so the screen can say how current the
    /// numbers are. The server reports no sync timestamp of its own.
    @AppStorage("retroAchievementsLastRefresh") private var lastRefresh: Double = 0
    @State private var usernameDraft = ""
    @State private var isSaving = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @FocusState private var usernameFocused: Bool

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.refreshUseCase = factory.makeRefreshRetroAchievementsUseCase()
        self.setUsernameUseCase = factory.makeSetRetroAchievementsUsernameUseCase()
    }

    private var linkedUsername: String? {
        appData.currentUser?.linkedRetroAchievementsUsername
    }

    private var canSaveUsername: Bool {
        let trimmed = usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != linkedUsername && !isSaving
    }

    var body: some View {
        Form {
            accountSection

            if linkedUsername != nil {
                progressSection
                refreshSection
            }

            profileSection
        }
        .navigationTitle("RetroAchievements")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { usernameDraft = linkedUsername ?? "" }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: linkedUsername == nil ? "trophy" : "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(linkedUsername == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(linkedUsername ?? "Not linked")
                        .font(.headline)
                    Text(linkedUsername == nil ? "No account linked yet" : "Linked RetroAchievements account")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            TextField("RetroAchievements username", text: $usernameDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($usernameFocused)
                .onSubmit { Task { await saveUsername() } }

            Button {
                usernameFocused = false
                Task { await saveUsername() }
            } label: {
                HStack {
                    Text(linkedUsername == nil ? "Link account" : "Save")
                    Spacer()
                    if isSaving { ProgressView() }
                }
            }
            .disabled(!canSaveUsername)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("RetroAchievements account")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your name on retroachievements.org. This is not your RomM login.")
                Text("There is no password to enter: the RomM server talks to RetroAchievements with its own API key, so it only needs the name to look your progress up.")
                if linkedUsername != nil {
                    Text("The server has no way to remove a linked account, so this name can be changed but not cleared.")
                }
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        let summary = appData.currentUser?.retroAchievementsSummary

        Section("Progress") {
            LabeledContent("Games tracked", value: (summary?.gameCount ?? 0).formatted())
            LabeledContent("Achievements earned", value: (summary?.earnedCount ?? 0).formatted())
            LabeledContent("In hardcore mode", value: (summary?.hardcoreCount ?? 0).formatted())
        }
    }

    @ViewBuilder
    private var refreshSection: some View {
        Section {
            Button {
                Task { await refresh(incremental: true) }
            } label: {
                HStack {
                    Label("Refresh progress", systemImage: "arrow.clockwise")
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                    }
                }
            }
            .disabled(isRefreshing)

            Button {
                Task { await refresh(incremental: false) }
            } label: {
                Label("Full resync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isRefreshing)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Sync")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if lastRefresh > 0 {
                    Text("Last refreshed \(Date(timeIntervalSince1970: lastRefresh).formatted(date: .abbreviated, time: .shortened)).")
                }
                Text("A refresh only picks up games whose totals changed. A full resync reads every game again and takes considerably longer.")
            }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if let user = appData.currentUser,
           user.lastLogin != nil || user.lastActive != nil || user.createdAt != nil {
            Section {
                if let lastLogin = user.lastLogin {
                    LabeledContent("Last login", value: lastLogin.formatted(date: .abbreviated, time: .shortened))
                }
                if let lastActive = user.lastActive {
                    LabeledContent("Last active", value: lastActive.formatted(date: .abbreviated, time: .shortened))
                }
                if let createdAt = user.createdAt {
                    LabeledContent("Member since", value: createdAt.formatted(date: .abbreviated, time: .omitted))
                }
            } header: {
                Text("RomM profile")
            } footer: {
                Text("These dates belong to your RomM account, not to RetroAchievements.")
            }
        }
    }

    // MARK: - Actions

    private func saveUsername() async {
        guard let userId = appData.currentUser?.id, canSaveUsername else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let user = try await setUsernameUseCase.execute(userId: userId, username: usernameDraft)
            appData.updateUser(user)
            usernameDraft = user?.linkedRetroAchievementsUsername ?? usernameDraft
            logger.info("RetroAchievements account linked")
            // A fresh link has no progression yet, so fetch it right away
            // instead of leaving the screen showing three zeroes.
            await refresh(incremental: false)
        } catch {
            logger.error("Linking RetroAchievements account failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func refresh(incremental: Bool) async {
        guard let userId = appData.currentUser?.id else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let user = try await refreshUseCase.execute(userId: userId, incremental: incremental)
            appData.updateUser(user)
            lastRefresh = Date().timeIntervalSince1970
            logger.info("RetroAchievements progression refreshed")
        } catch {
            logger.error("Refreshing RetroAchievements failed: \(error)")
            errorMessage = "Could not refresh: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        RetroAchievementsSettingsView()
            .environmentObject(AppData())
    }
}
