//
//  CollectionDetailView.swift
//  romm
//
//  Created by Ilyas Hallak on 23.08.25.
//

import SwiftUI


struct CollectionDetailView: View {
    let collection: Collection
    @State private var viewModel: CollectionDetailViewModel
    @State private var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "selectedViewMode") ?? ViewMode.smallCard.rawValue) ?? .smallCard
    @State private var searchText = ""
    
    init(collection: Collection) {
        self.collection = collection
        self._viewModel = State(wrappedValue: CollectionDetailViewModel(collectionId: collection.id))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            switch viewModel.viewState {
            case .loading:
                LoadingRomListView(message: "Loading collection ROMs...")
                
            case .loaded(let roms), .loadingMore(let roms):
                ZStack {
                    GenericRomListView(
                        roms: filteredRoms(from: roms),
                        viewMode: viewMode,
                        onRefresh: {
                            await viewModel.refreshRoms()
                        },
                        onLoadMore: {
                            await viewModel.loadMoreRomsIfNeeded()
                        },
                        onSort: { orderBy, orderDir in
                            await viewModel.sortRoms(orderBy: orderBy, orderDir: orderDir)
                        },
                        currentOrderBy: viewModel.currentOrderBy,
                        currentOrderDir: viewModel.currentOrderDir,
                        canLoadMore: viewModel.canLoadMore,
                        charIndex: viewModel.charIndex,
                        selectedChar: viewModel.selectedChar,
                        onCharTapped: { char in
                            await viewModel.filterByChar(char)
                        }
                    )
                    
                    // Loading indicator when loading more
                    if case .loadingMore = viewModel.viewState {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                LoadingView("Loading more...")
                                    .padding(12)
                                    .background(Color(.systemBackground).opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2)
                                Spacer()
                            }
                            .padding(.bottom, 50)
                        }
                    }
                }
                
            case .empty(let message):
                EmptyRomListView(
                    title: "No ROMs Found",
                    message: message,
                    iconName: "folder"
                )
                
            case .error:
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .opaqueNavigationBar()
        .searchableWhen(loadedRoms.count > 10, text: $searchText, prompt: "Search \(collection.name)")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Sort/Filter Button
                Button(action: {
                    // Placeholder für Sort/Filter action
                }) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .medium))
                }
                
                // View Mode Toggle Button
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

                        // Save view mode preference asynchronously
                        let selectedMode = viewMode
                        Task.detached {
                            let asyncDefaults = AsyncUserDefaults.shared
                            await asyncDefaults.set(selectedMode.rawValue, forKey: "selectedViewMode")
                        }
                    }
                }) {
                    Image(systemName: viewMode.icon)
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .task {
            // Guard: Only load if not already loaded or loading
            // This prevents unnecessary reloading when navigating back
            guard case .loading = viewModel.viewState else { return }
            await viewModel.loadRoms()
        }
        .alert("Error", isPresented: Binding(
            get: { if case .error = viewModel.viewState { return true }; return false },
            set: { if !$0 { viewModel.dismissError() } }
        ), actions: {
            Button("Retry") {
                Task { await viewModel.loadRoms() }
            }
            Button("Dismiss", role: .cancel) { }
        }, message: {
            if case .error(let msg) = viewModel.viewState { Text(msg) }
        })
    }
    
    private var loadedRoms: [Rom] {
        switch viewModel.viewState {
        case .loaded(let roms), .loadingMore(let roms):
            return roms
        default:
            return []
        }
    }

    private func filteredRoms(from roms: [Rom]) -> [Rom] {
        if searchText.isEmpty {
            return roms
        } else {
            return roms.filter { rom in
                rom.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}