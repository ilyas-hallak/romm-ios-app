//
//  SettingsView.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI

/// The app's own settings. Who is signed in, which server, and the way out of
/// both live in ``AccountSheet``, which is also what opens this screen.
struct SettingsView: View {
    @EnvironmentObject var appData: AppData
    @State private var profileViewModel = ProfileViewModel()
    @StateObject private var experimentalSettings = ExperimentalFeatureSettings.shared
    @StateObject private var cloudSyncSettings = CloudSaveSyncSettings.shared
    @State private var showingWhatsNew = false
    private let updateStore: AppUpdateStore = DefaultDependencyFactory.shared.appUpdateStore
    private let enginePreference: PEmulatorEnginePreference = DefaultDependencyFactory.shared.enginePreference
    private let playTargetPreference: PPlayTargetPreference = DefaultDependencyFactory.shared.playTargetPreference
    /// Read on appear rather than computed, so coming back from the engine
    /// settings picks up a changed Play destination.
    @State private var playsOnDevice = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// The App Store build ships the libretro cores as a regular feature, so the
    /// section belongs to that target rather than to the receipt the build was
    /// installed with. Everywhere else it stays the TestFlight/Debug experiment
    /// it has been.
    private var showsEmulatorSection: Bool {
        #if APP_STORE
        return true
        #else
        return Bundle.main.isTestFlightBuild || Bundle.main.isDebugBuild
        #endif
    }

    /// True when Play runs the game here with a built-in engine, the only case
    /// a BIOS image is ever read. The web engine runs on the server, and an
    /// external app brings whatever it needs itself.
    ///
    /// The engine preference already coerces a stored `.web` away in builds
    /// without the web engine, so comparing against it is enough.
    private func refreshPlayDestination() {
        guard case .builtIn = playTargetPreference.current else {
            playsOnDevice = false
            return
        }
        playsOnDevice = enginePreference.current != .web
    }

    private var emulatorSectionFooter: String {
        #if APP_STORE
        return "Play ROMs directly in the app, or hand them to an emulator app you already have."
        #else
        return "Experimental: play ROMs directly in the app. Only available in TestFlight and Debug builds."
        #endif
    }
    
    var body: some View {
        @Bindable var profileVM = profileViewModel
        return List {
            // Platforms Section
            Section {
                Toggle(isOn: $profileVM.groupRomsByMetaId) {
                    HStack {
                        Image(systemName: "rectangle.stack")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Group ROMs")
                            Text("Group versions of the same ROM together in the gallery")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Platforms")
            }

            // App Settings Section
            Section("App Settings") {
                UpdateAvailableRow()

                Button {
                    showingWhatsNew = true
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Version History")
                    }
                    .foregroundStyle(.primary)
                }

                // Logging Configuration (TestFlight & Debug only)
                if Bundle.main.isTestFlightBuild || Bundle.main.isDebugBuild {
                    NavigationLink(destination: LoggingConfigurationView()) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Logging Configuration")
                        }
                    }
                }

                NavigationLink(destination: ImageCacheSettingsView()) {
                    HStack {
                        Image(systemName: "photo.stack")
                        Text("Image Cache Settings")
                    }
                }

                NavigationLink(destination: LicensesView()) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Licenses")
                    }
                }
            }

            // Emulator Section
            if showsEmulatorSection {
                Section {
                    Toggle(isOn: $experimentalSettings.isEmulatorEnabled) {
                        HStack {
                            Image(systemName: "gamecontroller")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("In-App Emulator")
                                Text("Plays ROMs directly in the app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if experimentalSettings.isEmulatorEnabled {
                        NavigationLink(destination: EmulatorEngineSettingsView()) {
                            HStack {
                                Image(systemName: "cpu.fill")
                                Text("Emulator Engine")
                            }
                        }

                        // Stays in every build: PlayStation and Dreamcast do not
                        // start without their BIOS, see LibretroBIOSRequirement,
                        // and the libretro cores ship App Store side too. Only
                        // shown while a game actually runs here, the row means
                        // nothing for the web engine or an external app.
                        if playsOnDevice {
                            NavigationLink(destination: BIOSSettingsView()) {
                                HStack {
                                    Image(systemName: "cpu")
                                    Text("BIOS Files")
                                }
                            }
                        }

                        // Skins need a DeltaCore to inspect the .deltaskin, which
                        // the App Store build does not have, so the page would
                        // only ever come back empty there.
                        #if !APP_STORE
                        NavigationLink(destination: ControllerSkinsSettingsView()) {
                            HStack {
                                Image(systemName: "paintbrush.fill")
                                Text("Controller Skins")
                            }
                        }
                        #endif

                        NavigationLink(destination: ExternalDisplaySettingsView()) {
                            HStack {
                                Image(systemName: "tv")
                                Text("Play on TV")
                            }
                        }

                        NavigationLink(destination: RetroAchievementsSettingsView()) {
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("RetroAchievements")
                                    Text(appData.currentUser?.linkedRetroAchievementsUsername ?? "No account linked")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Toggle(isOn: $cloudSyncSettings.isEnabled) {
                            HStack {
                                Image(systemName: "icloud.and.arrow.up")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cloud Save Sync")
                                    Text("Sync game saves and save states with the RomM server")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Emulator")
                } footer: {
                    Text(emulatorSectionFooter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                VStack(spacing: 4) {
                    Text("v\(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Text("From Bremen with")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("♥")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Link("Ilyas Hallak", destination: URL(string: "https://ilyashallak.de")!)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            refreshPlayDestination()
        }
        .sheet(isPresented: $showingWhatsNew) {
            // The whole history from Settings, and no mark-seen side effect.
            ChangelogView(markdown: updateStore.changelog, mode: .versionHistory)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppData())
}
