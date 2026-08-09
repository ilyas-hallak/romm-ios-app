//
//  SettingsView.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI
import os

struct SettingsView: View {
    private let logger = Logger.ui
    @EnvironmentObject var appData: AppData
    @State private var profileViewModel = ProfileViewModel()
    @StateObject private var experimentalSettings = ExperimentalFeatureSettings.shared
    @StateObject private var cloudSyncSettings = CloudSaveSyncSettings.shared
    @State private var showingLogoutAlert = false
    @State private var showingResetAlert = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        @Bindable var profileVM = profileViewModel
        return List {
            // User Section
            if let user = appData.currentUser {
                Section("User") {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.username)
                                .font(.headline)
                            
                            Text("Active User")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Logout")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            
            // Server Section
            if let config = appData.currentConfiguration {
                Section("Server") {
                    HStack {
                        Image(systemName: "server.rack")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Server URL")
                            Text(config.serverURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "person")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Username")
                            Text(config.username)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reset Configuration")
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            
            // Statistics Section
            Section("Statistics") {
                NavigationLink(destination: StatsView()) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                        Text("Server Statistics")
                    }
                }
            }

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
                NavigationLink(destination: LoggingConfigurationView()) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Logging Configuration")
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
                        Text("Lizenzen")
                    }
                }
            }

            // Emulator Section (TestFlight & Debug only)
            if Bundle.main.isTestFlightBuild || Bundle.main.isDebugBuild {
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

                        NavigationLink(destination: BIOSSettingsView()) {
                            HStack {
                                Image(systemName: "cpu")
                                Text("BIOS Files")
                            }
                        }

                        Toggle(isOn: $cloudSyncSettings.isEnabled) {
                            HStack {
                                Image(systemName: "icloud.and.arrow.up")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cloud Sync for Saves")
                                    Text("Sync save files and save states with the RomM server")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Emulator")
                } footer: {
                    Text("Experimental: play ROMs directly in the app. Only available in TestFlight and Debug builds.")
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
                resetConfiguration()
            }
        } message: {
            Text("This will delete all configuration settings including your server connection and credentials. You will be returned to the setup screen.")
        }
    }
    
    private func resetConfiguration() {
        logger.info("Resetting configuration...")
        
        // Use ProfileViewModel's restart setup method
        profileViewModel.restartSetup()
        
        logger.info("Configuration reset complete")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppData())
}