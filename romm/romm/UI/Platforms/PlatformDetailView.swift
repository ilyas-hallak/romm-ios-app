//
//  PlatformDetailView.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI


struct PlatformDetailView: View {
    
    let platform: Platform
    
    @State private var viewModel = PlatformDetailViewModel()
    
    @State private var showingSortSheet = false
    
    // Filter state
    @State private var filterStates = FilterStates()

    @State private var searchText = ""
    
    // Check if custom sorting is active (not default name/asc)
    private var isCustomSortingActive: Bool {
        viewModel.currentOrderBy != "name" || viewModel.currentOrderDir != "asc"
    }
    
    // Check if any filters are active
    private var isFilterActive: Bool {
        filterStates.showUnmatched ||
        filterStates.showMatched ||
        filterStates.showFavourites ||
        filterStates.showDuplicates ||
        filterStates.showMissing ||
        filterStates.showVerified ||
        filterStates.showRetroAchievements ||
        filterStates.selectedGenre != nil ||
        filterStates.selectedFranchise != nil ||
        filterStates.selectedCollection != nil ||
        filterStates.selectedCompany != nil ||
        filterStates.selectedAgeRating != nil ||
        filterStates.selectedRegion != nil ||
        filterStates.selectedLanguage != nil ||
        filterStates.selectedStatus != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            switch viewModel.viewState {
            case .loading:
                // Only show full loading screen if we have no ROMs at all
                if viewModel.hasLoadedRoms {
                    // Show content while refreshing in background
                    RomListWithSectionIndex(
                        roms: viewModel.lastLoadedRoms,
                        viewMode: viewModel.viewMode,
                        onRefresh: {
                            await viewModel.refreshRoms()
                        },
                        onLoadMore: {
                            await viewModel.loadMoreRomsIfNeeded()
                        },
                        charIndex: viewModel.charIndex,
                        selectedChar: viewModel.selectedChar,
                        onCharTapped: { char in
                            await viewModel.filterByChar(char, platformId: platform.id)
                        },
                        onSort: { orderBy, orderDir in
                            await viewModel.sortRoms(orderBy: orderBy, orderDir: orderDir)
                        },
                        currentOrderBy: viewModel.currentOrderBy,
                        currentOrderDir: viewModel.currentOrderDir,
                        canLoadMore: viewModel.canLoadMore,
                        platform: platform
                    )
                } else {
                    // Show skeleton loading based on viewMode
                    skeletonLoadingView
                }
                
            case .loaded(let roms), .loadingMore(let roms):
                RomListWithSectionIndex(
                    roms: roms,
                    viewMode: viewModel.viewMode,
                    onRefresh: {
                        await viewModel.refreshRoms()
                    },
                    onLoadMore: {
                        await viewModel.loadMoreRomsIfNeeded()
                    },
                    charIndex: viewModel.charIndex,
                    selectedChar: viewModel.selectedChar,
                    onCharTapped: { char in
                        await viewModel.filterByChar(char, platformId: platform.id)
                    },
                    onSort: { orderBy, orderDir in
                        await viewModel.sortRoms(orderBy: orderBy, orderDir: orderDir)
                    },
                    currentOrderBy: viewModel.currentOrderBy,
                    currentOrderDir: viewModel.currentOrderDir,
                    canLoadMore: viewModel.canLoadMore,
                    platform: platform
                )
                
            case .empty(let message):
                EmptyRomsView(message: message)
                
            case .error:
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle(platform.name)
        .navigationBarTitleDisplayMode(.large)
        .opaqueNavigationBar()
        .searchableWhen(getCurrentRoms().count > 10, text: $searchText, prompt: "Search \(platform.name)")
        .onSubmit(of: .search) {
            Task { await viewModel.searchRoms(query: searchText, platformId: platform.id) }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                Task { await viewModel.loadRoms(for: platform.id, refresh: true) }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Sort/Filter Button
                Button(action: {
                    showingSortSheet = true
                }) {
                    ZStack {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 16, weight: .medium))
                        
                        // Active sorting/filtering indicator
                        if isCustomSortingActive || isFilterActive {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                
                // View Mode Toggle Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let newMode: ViewMode
                        switch viewModel.viewMode {
                        case .smallCard:
                            newMode = .bigCard
                        case .bigCard:
                            newMode = .table
                        case .table:
                            newMode = .smallCard
                        }
                        viewModel.updateViewMode(newMode)
                    }
                }) {
                    Image(systemName: viewModel.viewMode.icon)
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .sheet(isPresented: $showingSortSheet) {
            let currentRoms = getCurrentRoms()
            let filterOptions = getAvailableFilterOptions(from: currentRoms)
            
            FilterView(
                filterOptions: filterOptions,
                filterStates: $filterStates,
                onReset: {
                    filterStates = FilterStates()
                    showingSortSheet = false // Close sheet first
                    Task {
                        // Reset filters means load all ROMs without filters
                        await viewModel.loadRoms(for: platform.id, refresh: true)
                    }
                },
                onApply: {
                    showingSortSheet = false // Close sheet first
                    Task {
                        await viewModel.applyFilters(filterStates, platformId: platform.id)
                    }
                }
            )
        }
        .onAppear {
            // Only load if we don't have data for this platform yet
            if !viewModel.hasDataFor(platformId: platform.id) {
                Task {
                    await viewModel.loadRoms(for: platform.id)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { if case .error = viewModel.viewState { return true }; return false },
            set: { if !$0 { viewModel.dismissError() } }
        ), actions: {
            Button("Retry") {
                Task { await viewModel.loadRoms(for: platform.id) }
            }
            Button("Dismiss", role: .cancel) { }
        }, message: {
            if case .error(let msg) = viewModel.viewState { Text(msg) }
        })
    }
    
    
    private func getStatusSet(for rom: Rom) -> Set<String> {
        var statuses: Set<String> = []
        
        if rom.isFavourite {
            statuses.insert("Favourite")
        }
        if rom.hasRetroAchievements {
            statuses.insert("RetroAchievements")
        }
        if rom.isPlayable {
            statuses.insert("Playable")
        } else {
            statuses.insert("Not Playable")
        }
        
        return statuses
    }
    
    private func getAvailableFilterOptions(from roms: [Rom]) -> FilterOptions {
        var genres: Set<String> = []
        var franchises: Set<String> = []
        var companies: Set<String> = []
        var ageRatings: Set<String> = []
        var languages: Set<String> = []
        var regions: Set<String> = []
        var statuses: Set<String> = []
        
        // Extract all available data from the ROM model
        for rom in roms {
            genres.formUnion(rom.genres)
            franchises.formUnion(rom.franchises)
            companies.formUnion(rom.companies)
            ageRatings.formUnion(rom.ageRatings)
            languages.formUnion(rom.languages)
            regions.formUnion(rom.regions)
            statuses.formUnion(getStatusSet(for: rom))
        }
        
        return FilterOptions(
            genres: Array(genres).sorted(),
            franchises: Array(franchises).sorted(),
            collections: [], // Collections not available in ROM model yet
            companies: Array(companies).sorted(),
            ageRatings: Array(ageRatings).sorted(),
            regions: Array(regions).sorted(),
            languages: Array(languages).sorted(),
            statuses: Array(statuses).sorted()
        )
    }
    
    private func getCurrentRoms() -> [Rom] {
        switch viewModel.viewState {
        case .loaded(let roms), .loadingMore(let roms):
            return roms
        case .loading:
            return viewModel.lastLoadedRoms
        default:
            return []
        }
    }

    @ViewBuilder
    private var skeletonLoadingView: some View {
        switch viewModel.viewMode {
        case .bigCard:
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 16) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonBigRomCardView()
                    }
                }
                .padding(16)
            }

        case .smallCard:
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0..<12, id: \.self) { _ in
                        SkeletonSmallRomCardView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

        case .table:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<15, id: \.self) { _ in
                        SkeletonTableRomRowView()
                    }
                }
            }
        }
    }
}

struct PlatformHeaderView: View {
    let platform: Platform
    @Binding var viewMode: ViewMode
    
    var body: some View {
        HStack(spacing: 12) {

            Image(platform.slug)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 40, height: 40)

            Button(action: {
                // Placeholder action
            }) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch viewMode {
                    case .smallCard:
                        viewMode = .bigCard
                    case .bigCard:
                        viewMode = .table
                    case .table:
                        viewMode = .smallCard
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: viewMode.icon)
                        .font(.system(size: 14, weight: .medium))
                    Text(viewMode.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}


struct SmallRomCardView: View {
    let rom: Rom
    
    var body: some View {
        HStack(spacing: 12) {
            // ROM Cover Image
            CachedKFImage(urlString: rom.urlCover) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundColor(.gray)
                            .font(.title2)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            // ROM Information
            VStack(alignment: .leading, spacing: 4) {
                Text(rom.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 8) {
                    if let year = rom.releaseYear {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(year)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let rating = rom.rating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Status Icons
            VStack(spacing: 4) {
                RomStatusIcons(rom: rom)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct TableRomRowView: View {
    let rom: Rom
    
    var body: some View {
        HStack {
            Text(rom.name)
                .font(.body)
                .lineLimit(1)
            
            Spacer()
            
            if let year = rom.releaseYear {
                Text("\(year)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            RomStatusIcons(rom: rom)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

struct RomStatusIcons: View {
    let rom: Rom
    @EnvironmentObject private var appData: AppData
    
    var body: some View {
        HStack(spacing: 4) {
            if rom.isFavourite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if rom.hasRetroAchievements {
                retroAchievementsStatus
            }                        
        }
    }

    @ViewBuilder
    private var retroAchievementsStatus: some View {
        if let progression = appData.currentUser?.retroAchievementsProgression(for: rom.retroAchievementsGameId) {
            let maximum = progression.maximumCount ?? 0
            let awarded = progression.awardedCount ?? progression.earnedAchievements.count
            let isComplete = maximum > 0 && awarded >= maximum

            Image(systemName: isComplete ? "checkmark.seal.fill" : "circle.lefthalf.filled")
                .foregroundStyle(isComplete ? .green : .orange)
                .font(.caption)
                .accessibilityLabel(isComplete ? "RetroAchievements complete" : "RetroAchievements in progress")
        } else {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .accessibilityLabel("RetroAchievements available")
        }
    }
}

struct EmptyRomsView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No ROMs Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


#Preview {
    NavigationStack {
        PlatformDetailView(platform: Platform(
            id: 1,
            name: "Nintendo Switch",
            slug: "nintendo-switch",
            romCount: 42
        ))
    }
}
