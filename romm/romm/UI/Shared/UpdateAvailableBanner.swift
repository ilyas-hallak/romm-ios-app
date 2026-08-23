//
//  UpdateAvailableBanner.swift
//  romm
//
//  Non-blocking update nudge for TestFlight users. Rendered inline as the first
//  card on Home and as a compact Settings row, never as an overlay: an overlay
//  would fight the navigation bar and the floating tab bar.
//

import SwiftUI

// MARK: - Banner

/// Inline card for the top of a scroll view. Renders to nothing when there is no
/// pending update, so callers can embed it unconditionally.
struct UpdateAvailableBanner: View {
    @State private var service = UpdateCheckService.shared

    var body: some View {
        if let update = service.availableUpdate {
            Button {
                TestFlightLink.open()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Update available")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Build \(update.build) is ready in TestFlight. Tap to open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                    Button {
                        service.dismissCurrentUpdate()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss update notice")
                }
                .padding(14)
                // secondarySystemGroupedBackground is the card colour on a grouped
                // background; .background.secondary is nearly invisible there.
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: service.availableUpdate)
        }
    }
}

// MARK: - Row (for Settings)

/// A compact Settings-list row that shows when an update is available.
/// Renders to nothing when there is no pending update.
struct UpdateAvailableRow: View {
    @State private var service = UpdateCheckService.shared

    var body: some View {
        if let update = service.availableUpdate {
            Button {
                TestFlightLink.open()
            } label: {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available")
                            .foregroundStyle(.primary)
                        Text("Build \(update.build) is ready in TestFlight")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Opening TestFlight

enum TestFlightLink {
    private static let testFlight = URL(string: "itms-beta://")!
    private static let appStore = URL(string: "https://apps.apple.com/app/testflight/id899247664")!

    /// Opens the TestFlight app, falling back to its App Store page when it is not
    /// installed. `canOpenURL` for itms-beta needs LSApplicationQueriesSchemes, so we
    /// just attempt the open and use the completion handler as the probe.
    static func open() {
        UIApplication.shared.open(testFlight, options: [:]) { success in
            if !success {
                UIApplication.shared.open(appStore)
            }
        }
    }
}

// MARK: - Previews

#Preview("Banner") {
    ScrollView {
        VStack(spacing: 16) {
            UpdateAvailableBanner()
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(height: 160)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
    .onAppear {
        UpdateCheckService.shared.availableUpdate = .init(
            build: 52, version: "1.0", date: "2026-08-23", entries: []
        )
    }
}

#Preview("Row") {
    NavigationStack {
        List {
            Section("App Settings") {
                UpdateAvailableRow()
                Text("Other setting")
            }
        }
        .navigationTitle("Settings")
    }
    .onAppear {
        UpdateCheckService.shared.availableUpdate = .init(
            build: 52, version: "1.0", date: "2026-08-23", entries: []
        )
    }
}
