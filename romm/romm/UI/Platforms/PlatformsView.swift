//
//  PlatformsView.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI

struct PlatformsView: View {

    @State private var platformsViewModel = PlatformsViewModel()

    @EnvironmentObject var appData: AppData

    @State private var searchText = ""

    var body: some View {
        ZStack {
            if platformsViewModel.isLoading && platformsViewModel.platforms.isEmpty {
                // Show skeleton loading
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<8, id: \.self) { _ in
                            SkeletonPlatformRowView()
                        }
                    }
                    .padding()
                }
            } else if platformsViewModel.platforms.isEmpty {
                EmptyPlatformsView()
            } else {
                PlatformListView(
                    platforms: platformsViewModel.platforms,
                    isLoading: platformsViewModel.isLoading,
                    viewModel: platformsViewModel,
                    searchText: searchText
                )
            }
        }
        .navigationTitle("Platforms")
        .searchableWhen(platformsViewModel.platforms.filter { $0.romCount > 0 }.count > 10, text: $searchText, prompt: "Search platforms")
        .onAppear {
            // Load platforms on first appear for better performance
            // This prevents blocking during ViewModel initialization
            if platformsViewModel.platforms.isEmpty && !platformsViewModel.isLoading {
                Task {
                    await platformsViewModel.loadPlatforms()
                }
            }
        }
        .alert("Error", isPresented: .constant(platformsViewModel.errorMessage != nil)) {
            Button("Retry") {
                Task {
                    await platformsViewModel.refreshPlatforms()
                }
                platformsViewModel.clearError()
            }
            Button("OK") {
                platformsViewModel.clearError()
            }
        } message: {
            Text(platformsViewModel.errorMessage ?? "An error occurred")
        }
    }
}

struct PlatformListView: View {
    let platforms: [Platform]
    let isLoading: Bool
    let viewModel: PlatformsViewModel
    let searchText: String

    // Filter platforms with at least one ROM, then by the search query
    private var nonEmptyPlatforms: [Platform] {
        let nonEmpty = platforms.filter { $0.romCount > 0 }
        guard !searchText.isEmpty else { return nonEmpty }
        return nonEmpty.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(nonEmptyPlatforms) { platform in
                    NavigationLink {
                        PlatformDetailView(platform: platform)
                    } label: {
                        PlatformRowView(platform: platform)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await viewModel.refreshPlatforms()
        }
    }
}

struct PlatformRowView: View {
    let platform: Platform
    
    var body: some View {
        HStack {
            // Platform Logo
            Image(platform.slug)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            
            
            // Platform Info
            VStack(alignment: .leading, spacing: 4) {
                Text(platform.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text("\(platform.romCount) ROMs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Navigation Indicator
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct EmptyPlatformsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Platforms Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Add some platforms to get started with your ROM collection")
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
    PlatformsView()
        .environmentObject(AppData())
}
