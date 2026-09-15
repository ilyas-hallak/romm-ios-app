//
//  LibraryScanStartSheet.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import SwiftUI

/// Picks what to scan. The default is a quick scan over the whole library,
/// which is what an empty platform list means to the server.
struct LibraryScanStartSheet: View {
    @Bindable var viewModel: LibraryScanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(LibraryScanType.allCases) { type in
                        Button {
                            viewModel.selectedScanType = type
                        } label: {
                            scanTypeRow(type)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Scan type")
                }

                Section {
                    Button {
                        viewModel.selectAllPlatforms()
                    } label: {
                        selectionRow(
                            title: "All platforms",
                            subtitle: "Let the server walk the whole library",
                            isSelected: viewModel.selectedPlatformIds.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    if viewModel.isLoadingPlatforms {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading platforms...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    ForEach(viewModel.platforms) { platform in
                        Button {
                            viewModel.togglePlatform(platform)
                        } label: {
                            selectionRow(
                                title: platform.displayName,
                                subtitle: platform.romCount > 0 ? "\(platform.romCount) ROMs" : nil,
                                isSelected: viewModel.selectedPlatformIds.contains(platform.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Platforms")
                } footer: {
                    Text("Pick single platforms to keep the scan short, or leave it on all platforms.")
                }
            }
            .navigationTitle("Start Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        viewModel.startScan()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func scanTypeRow(_ type: LibraryScanType) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: type.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 24, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(type.displayName)
                    .font(.body)
                    .foregroundColor(.primary)

                Text(type.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if viewModel.selectedScanType == type {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func selectionRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
