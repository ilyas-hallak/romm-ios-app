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
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeView()
                }
            }

            Tab("Platforms", systemImage: "gamecontroller") {
                NavigationStack {
                    PlatformsView()
                }
            }

            Tab("Collections", systemImage: "books.vertical") {
                NavigationStack {
                    CollectionView()
                }
            }

            Tab("Devices", systemImage: "server.rack") {
                NavigationStack {
                    SFTPDevicesView()
                }
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
    }
}
