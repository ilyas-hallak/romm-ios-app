//
//  AppData.swift
//  romm
//
//  Created by Ilyas Hallak on 08.08.25.
//

import Foundation
import Combine

enum AppTab: Hashable {
    case home
    case platforms
    case collections
    case downloads
    case search
}

@MainActor
class AppData: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String?
    @Published var currentConfiguration: AppConfiguration?
    @Published var isLoading: Bool = false
    @Published var selectedTab: AppTab = .home

    init() {}

    // Update methods for AppViewModel to call
    func updateUser(_ user: User?) {
        currentUser = user
    }

    func updateAuthState(_ authenticated: Bool) {
        isAuthenticated = authenticated
    }

    func updateError(_ error: String?) {
        errorMessage = error
    }

    func updateConfiguration(_ configuration: AppConfiguration?) {
        currentConfiguration = configuration
    }

    func updateLoading(_ loading: Bool) {
        isLoading = loading
    }
}
