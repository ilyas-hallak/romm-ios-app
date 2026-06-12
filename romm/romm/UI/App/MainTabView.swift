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
    
    init(dependencyFactory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.dependencyFactory = dependencyFactory
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

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
    }
}
