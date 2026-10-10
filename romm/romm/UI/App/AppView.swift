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
    @State private var appViewModel: AppViewModel
    /// `AppData` is a plain `ObservableObject`, not `@Observable` like `AppViewModel`,
    /// so without this it wouldn't trigger a redraw on its own when `errorMessage` changes.
    @ObservedObject private var appData: AppData
    @Environment(\.scenePhase) private var scenePhase

    /// `appViewModel`'s default is built inside the body, not as a parameter
    /// default value: a default-value expression doesn't inherit this init's
    /// `@MainActor` isolation, and `AppViewModel()` requires it.
    @MainActor
    init(appViewModel: AppViewModel? = nil) {
        let viewModel = appViewModel ?? AppViewModel()
        _appViewModel = State(initialValue: viewModel)
        _appData = ObservedObject(wrappedValue: viewModel.appData)
    }

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
                    .alert(
                        "Logged Out",
                        isPresented: Binding(
                            get: { appViewModel.setupNotice != nil },
                            set: { if !$0 { appViewModel.setupNotice = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(appViewModel.setupNotice ?? "")
                    }
                
            case .authenticated:
                MainTabView()
                    .environmentObject(appData)
                
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
                logger.debug("App became active - checking server address and version")
                Task {
                    await appViewModel.appDidBecomeActive()
                }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { appData.errorMessage != nil },
                set: { if !$0 { appViewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(appData.errorMessage ?? "")
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
        .sheet(item: Binding(
            get: { IncomingRomFileState.shared.pendingFile },
            set: { IncomingRomFileState.shared.pendingFile = $0 }
        )) { file in
            RomUploadSheet(viewModel: RomUploadSheetViewModel(file: file))
        }
    }
}

#Preview {
    AppView()
}
