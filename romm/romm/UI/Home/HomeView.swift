//
//  HomeView.swift
//  romm
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @EnvironmentObject var appData: AppData

    var body: some View {
        contentView
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                if !viewModel.hasStartedLoading {
                    await viewModel.load()
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                UpdateAvailableBanner()
                HomeRomSection(
                    title: "Continue Playing",
                    roms: viewModel.continuePlaying,
                    isLoading: viewModel.isLoadingContinuePlaying
                )
                HomeRomSection(
                    title: "Recently Added",
                    roms: viewModel.recentlyAdded,
                    isLoading: viewModel.isLoadingRecentlyAdded
                )
                HomePlatformSection(
                    platforms: viewModel.platforms,
                    isLoading: viewModel.isLoadingPlatforms
                )
                HomeCollectionSection(
                    collections: viewModel.collections,
                    coverURL: { viewModel.coverURL(for: $0) },
                    isLoading: viewModel.isLoadingCollections
                )
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Skeleton

private struct SkeletonCard: View {
    let width: CGFloat
    let height: CGFloat
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: shimmer
                        ? [Color(.systemFill), Color(.secondarySystemFill), Color(.systemFill)]
                        : [Color(.secondarySystemFill), Color(.systemFill), Color(.secondarySystemFill)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}

// MARK: - Sections

private struct HomeSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .padding(.horizontal, 16)
    }
}

private struct HomeRomSection: View {
    let title: String
    let roms: [Rom]
    let isLoading: Bool

    var body: some View {
        if isLoading || !roms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        if isLoading {
                            ForEach(0..<5, id: \.self) { _ in
                                VStack(spacing: 8) {
                                    SkeletonCard(width: 200, height: 130)
                                    SkeletonCard(width: 160, height: 14)
                                        .clipShape(Capsule())
                                }
                            }
                        } else {
                            ForEach(roms) { rom in
                                NavigationLink(destination: RomDetailView(rom: rom)) {
                                    BigRomCardView(rom: rom)
                                        .frame(width: 200)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct HomePlatformSection: View {
    let platforms: [Platform]
    let isLoading: Bool

    var body: some View {
        if isLoading || !platforms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "Platforms")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        if isLoading {
                            ForEach(0..<6, id: \.self) { _ in
                                VStack(spacing: 8) {
                                    SkeletonCard(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    SkeletonCard(width: 80, height: 12)
                                        .clipShape(Capsule())
                                }
                                .frame(width: 124)
                            }
                        } else {
                            ForEach(platforms) { platform in
                                NavigationLink(destination: PlatformDetailView(platform: platform)) {
                                    HomePlatformCard(platform: platform)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct HomePlatformCard: View {
    let platform: Platform

    var body: some View {
        VStack(spacing: 8) {
            Image(platform.slug)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )

            Text(platform.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("\(platform.romCount) ROMs")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 124)
    }
}

private struct HomeCollectionSection: View {
    let collections: [Collection]
    let coverURL: (Collection) -> String?
    let isLoading: Bool

    var body: some View {
        if isLoading || !collections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "Collections")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        if isLoading {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 8) {
                                    SkeletonCard(width: 140, height: 140)
                                    SkeletonCard(width: 110, height: 12)
                                        .clipShape(Capsule())
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                        } else {
                            ForEach(collections) { collection in
                                NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                    HomeCollectionCard(collection: collection, coverURL: coverURL(collection))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct HomeCollectionCard: View {
    let collection: Collection
    let coverURL: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedKFImage(urlString: coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.2), Color.pink.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        Image(systemName: "folder.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                    )
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )

            Text(collection.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("\(collection.romCount) ROMs")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 140, alignment: .leading)
    }
}
