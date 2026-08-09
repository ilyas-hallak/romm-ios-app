//
//  AppView.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import SwiftUI
import os

struct AppView: View {
    private let logger = Logger.ui
    @State private var appViewModel = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appViewModel.appState {
            case .loading:
                LoadingView("Loading...")
                .onAppear {
                    Task {
                        await appViewModel.checkInitialState()
                    }
                }
                
            case .setup:
                SetupView(appViewModel: appViewModel)
                
            case .authenticated:
                MainTabView()
                    .environmentObject(appViewModel.appData)
                
            case .authenticationFailed:
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    VStack(spacing: 8) {
                        Text("Authentication Failed")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Your session has expired. Please set up your connection again.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Button("Restart Setup") {
                        logger.info("Restart Setup button tapped")
                        appViewModel.restartSetup()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                logger.debug("App became active - checking server version")
                Task {
                    await appViewModel.checkServerVersionOnForeground()
                }
            }
        }
        .alert(
            appViewModel.serverVersionAlert?.title ?? "Server Version Changed",
            isPresented: Binding(
                get: { appViewModel.serverVersionAlert != nil },
                set: { if !$0 { appViewModel.serverVersionAlert = nil } }
            ),
            presenting: appViewModel.serverVersionAlert
        ) { _ in
            Button("Continue") {
                appViewModel.continueWithServerVersionChange()
            }
            .keyboardShortcut(.defaultAction)

            Button("Logout", role: .destructive) {
                appViewModel.logoutFromServerVersionAlert()
            }
        } message: { alert in
            Text(alert.message)
        }
    }
}

#Preview {
    AppView()
}
