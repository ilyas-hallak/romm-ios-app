//
//  MainTabView.swift
//  romm
//
//  Created by Ilyas Hallak on 08.08.25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appData: AppData
    private let dependencyFactory: PDependencyFactory
    private let updateStore: AppUpdateStore
    @State private var showWhatsNew = false

    init(dependencyFactory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.dependencyFactory = dependencyFactory
        self.updateStore = dependencyFactory.appUpdateStore
    }

    var body: some View {
        TabView(selection: $appData.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack {
                    HomeView()
                }
            }

            Tab("Platforms", systemImage: "gamecontroller", value: AppTab.platforms) {
                NavigationStack {
                    PlatformsView()
                }
            }

            Tab("Collections", systemImage: "books.vertical", value: AppTab.collections) {
                NavigationStack {
                    CollectionView()
                }
            }

            Tab("Downloads", systemImage: "arrow.down.circle", value: AppTab.downloads) {
                NavigationStack {
                    LocalDeviceDetailView()
                }
            }
            .badge(DownloadQueueManager.shared.activeCount)

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
        .tabBarMinimizeOnScrollDown()
        .overlay {
            if let flight = appData.downloadFlight {
                DownloadFlightOverlay(flight: flight) {
                    appData.finishDownloadFlight(flight.id)
                }
                .id(flight.id)
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(
                entries: updateStore.whatsNewEntries,
                mode: .whatsNew,
                onClose: { updateStore.markWhatsNewSeen() }
            )
        }
        .task {
            updateStore.loadLocalState()
            if updateStore.shouldShowWhatsNew {
                showWhatsNew = true
            }
            await updateStore.checkForUpdates()
        }
    }
}

private extension View {
    /// Keeps the tab bar visible and lets it minimize (slide down) as the user
    /// scrolls content down — the native iOS 26 behavior. No-op on older OSes.
    @ViewBuilder
    func tabBarMinimizeOnScrollDown() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
