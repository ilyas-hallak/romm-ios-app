//
//  CollectionView.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI

struct CollectionView: View {
    @State private var collectionsViewModel = CollectionsViewModel()
    @EnvironmentObject var appData: AppData

    @State private var searchText = ""

    var body: some View {
        VStack {
            switch collectionsViewModel.viewState {
            case .loading:
                loadingView
            case .empty:
                emptyView
            case .loaded, .loadingMore:
                collectionsListView
            }
        }
        .navigationTitle("Collections")
        .searchableWhen(collectionsViewModel.virtualCollections.count + collectionsViewModel.collections.count > 10, text: $searchText, prompt: "Search collections")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    collectionsViewModel.showCreateCollection()
                }
            }
        }
        .sheet(isPresented: $collectionsViewModel.showingCreateCollection) {
            CreateCollectionView { createdCollection in
                collectionsViewModel.onCollectionCreated(createdCollection)
            }
        }
        .alert("Error", isPresented: .constant(collectionsViewModel.errorMessage != nil)) {
            Button("OK") {
                collectionsViewModel.clearError()
            }
        } message: {
            Text(collectionsViewModel.errorMessage ?? "")
        }
        .alert("Delete Collection", isPresented: .constant(collectionsViewModel.collectionToDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let collection = collectionsViewModel.collectionToDelete {
                    Task {
                        await collectionsViewModel.deleteCollection(collection)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                collectionsViewModel.hideDeleteConfirmation()
            }
        } message: {
            if let collection = collectionsViewModel.collectionToDelete {
                Text("Are you sure you want to delete '\(collection.name)'? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - View Builders
    
    @ViewBuilder
    private var loadingView: some View {
        List {
            Section("Virtual Collections") {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonCollectionRowView()
                }
            }

            Section("Custom Collections") {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonCollectionRowView()
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Collections found")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Your collections will appear here")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var collectionsListView: some View {
        List {
            virtualCollectionsSection
            customCollectionsSection
            loadingMoreIndicator
        }
        .refreshable {
            await collectionsViewModel.refreshCollections()
        }
        .task {
            // Load collections on first appear
            await collectionsViewModel.loadCollections()
        }
    }
    
    private var filteredVirtual: [VirtualCollection] {
        guard !searchText.isEmpty else { return collectionsViewModel.virtualCollections }
        return collectionsViewModel.virtualCollections.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredCollections: [Collection] {
        guard !searchText.isEmpty else { return collectionsViewModel.collections }
        return collectionsViewModel.collections.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private var virtualCollectionsSection: some View {
        if !filteredVirtual.isEmpty {
            Section("Virtual Collections") {
                ForEach(filteredVirtual, id: \.id) { virtualCollection in
                    NavigationLink {
                        VirtualCollectionDetailView(virtualCollection: virtualCollection)
                    } label: {
                        VirtualCollectionRowView(virtualCollection: virtualCollection)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var customCollectionsSection: some View {
        if !filteredCollections.isEmpty {
            Section("Custom Collections") {
                ForEach(filteredCollections, id: \.id) { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection)
                    } label: {
                        CollectionRowView(collection: collection, coverURL: collectionsViewModel.coverURL(for: collection))
                    }
                    .onAppear {
                        // Load more when approaching the end (only while not filtering)
                        if searchText.isEmpty && collection == collectionsViewModel.collections.last {
                            Task {
                                await collectionsViewModel.loadMoreCollectionsIfNeeded()
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        let collection = filteredCollections[index]
                        collectionsViewModel.showDeleteConfirmation(for: collection)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var loadingMoreIndicator: some View {
        if collectionsViewModel.isLoadingMore {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading more...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct CollectionRowView: View {
    let collection: Collection
    let coverURL: String?

    init(collection: Collection, coverURL: String? = nil) {
        self.collection = collection
        self.coverURL = coverURL ?? collection.urlCover
    }

    var body: some View {
        HStack(spacing: 12) {
            // Collection cover
            CachedKFImage(urlString: coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.2))
                    .overlay(
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(collection.romCount) ROM\(collection.romCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !collection.description.isEmpty {
                    Text(collection.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if collection.isPublic {
                Image(systemName: "globe")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct VirtualCollectionRowView: View {
    let virtualCollection: VirtualCollection
    
    var body: some View {
        HStack(spacing: 12) {
            // Virtual collection icon
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: collectionTypeIcon(virtualCollection.type))
                        .foregroundColor(.purple)
                        .font(.title2)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(virtualCollection.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(virtualCollection.romCount) ROM\(virtualCollection.romCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !virtualCollection.description.isEmpty {
                    Text(virtualCollection.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func collectionTypeIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "favorites", "favourite":
            return "heart.fill"
        case "recent":
            return "clock.fill"
        case "most_played", "mostplayed":
            return "chart.bar.fill"
        default:
            return "folder.fill"
        }
    }
}


#Preview {
    CollectionView()
        .environmentObject(AppData())
}
