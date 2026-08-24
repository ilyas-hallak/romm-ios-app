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
    private let store: AppUpdateStore

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.store = factory.appUpdateStore
    }

    var body: some View {
        if let update = store.availableUpdate {
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
                        store.dismissAvailableUpdate()
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
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.availableUpdate)
        }
    }
}

// MARK: - Row (for Settings)

/// A compact Settings-list row that shows when an update is available.
/// Renders to nothing when there is no pending update.
struct UpdateAvailableRow: View {
    private let store: AppUpdateStore

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.store = factory.appUpdateStore
    }

    var body: some View {
        if let update = store.availableUpdate {
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
