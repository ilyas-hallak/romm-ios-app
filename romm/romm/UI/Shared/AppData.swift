//
//  AppData.swift
//  romm
//
//  Created by Ilyas Hallak on 08.08.25.
//

import Foundation
import Combine
import CoreGraphics

enum AppTab: Hashable {
    case home
    case platforms
    case collections
    case downloads
    case search
}

/// A one-shot "cover flies into the Downloads tab" animation request.
/// `start` is the source frame in global (screen) coordinates. `tabBarMinimized`
/// is a snapshot of the tab-bar state at launch (there's no public API to query
/// it, so the source derives it from its scroll position) — the cover flies to
/// the collapsed pill in the leading corner when true, else to the Downloads icon.
struct DownloadFlight: Identifiable, Equatable {
    let id: UUID
    let coverURL: String?
    let start: CGRect
    let tabBarMinimized: Bool
}

@MainActor
class AppData: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String?
    @Published var currentConfiguration: AppConfiguration?
    @Published var isLoading: Bool = false
    @Published var selectedTab: AppTab = .home
    /// Active cover-fly-to-Downloads animation, or `nil` when idle.
    @Published var downloadFlight: DownloadFlight?

    init() {}

    /// Kick off the cover-fly animation from the given global source frame.
    func launchDownloadFlight(coverURL: String?, from start: CGRect, tabBarMinimized: Bool) {
        guard start != .zero else { return }
        downloadFlight = DownloadFlight(
            id: UUID(),
            coverURL: coverURL,
            start: start,
            tabBarMinimized: tabBarMinimized
        )
    }

    /// Clear the flight once its animation has landed.
    func finishDownloadFlight(_ id: UUID) {
        if downloadFlight?.id == id { downloadFlight = nil }
    }

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
