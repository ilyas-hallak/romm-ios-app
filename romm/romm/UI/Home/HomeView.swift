//
//  HomeView.swift
//  romm
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @EnvironmentObject var appData: AppData

    var body: some View {
        Group {
            switch viewModel.viewState {
            case .initial, .loading:
                loadingView
            case .empty:
                emptyView
            case .loaded:
                contentView
            }
        }
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
            if case .initial = viewModel.viewState {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !viewModel.continuePlaying.isEmpty {
                    HomeRomSection(title: "Continue Playing", roms: viewModel.continuePlaying)
                }
                if !viewModel.recentlyAdded.isEmpty {
                    HomeRomSection(title: "Recently Added", roms: viewModel.recentlyAdded)
                }
                if !viewModel.platforms.isEmpty {
                    HomePlatformSection(platforms: viewModel.platforms)
                }
                if !viewModel.collections.isEmpty {
                    HomeCollectionSection(collections: viewModel.collections)
                }
            }
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack {
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Nothing here yet")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(roms) { rom in
                        NavigationLink(destination: RomDetailView(rom: rom)) {
                            BigRomCardView(rom: rom)
                                .frame(width: 200)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct HomePlatformSection: View {
    let platforms: [Platform]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "Platforms")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(platforms) { platform in
                        NavigationLink(destination: PlatformDetailView(platform: platform)) {
                            HomePlatformCard(platform: platform)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "Collections")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(collections) { collection in
                        NavigationLink(destination: CollectionDetailView(collection: collection)) {
                            HomeCollectionCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct HomeCollectionCard: View {
    let collection: Collection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedKFImage(urlString: collection.urlCover) { image in
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
