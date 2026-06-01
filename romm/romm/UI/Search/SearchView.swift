//
//  SearchView.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI

struct SearchView: View {
    @State private var searchViewModel = SearchViewModel()
    @State private var searchText = ""

    var body: some View {
        searchContentView
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Enter ROM-Name")
            .onSubmit(of: .search) {
                searchViewModel.search(query: searchText)
            }
            .toolbar {
                keyboardToolbar
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { searchViewModel.errorMessage != nil },
                    set: { if !$0 { searchViewModel.clearError() } }
                )
            ) {
                Button("OK") { searchViewModel.clearError() }
            } message: {
                Text(searchViewModel.errorMessage ?? "")
            }
            .onChange(of: searchText) { _, newValue in
                searchViewModel.scheduleSearch(query: newValue)
            }
            .onDisappear {
                searchViewModel.cancelAllTasks()
            }
    }

    @ViewBuilder
    private var searchContentView: some View {
        VStack(spacing: 0) {
            if searchViewModel.isLoading {
                loadingView
            } else if searchText.isEmpty && searchViewModel.searchResults.isEmpty {
                emptyStateView
            } else if searchViewModel.searchResults.isEmpty && !searchText.isEmpty {
                noResultsView
            } else {
                searchResultsView
            }
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        LoadingView("Searching...", fillScreen: false)
        Spacer()
    }

    @ViewBuilder
    private var emptyStateView: some View {
        Spacer()
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("ROM-Search")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Use the search to find your favorite ROMs")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        Spacer()
    }

    @ViewBuilder
    private var noResultsView: some View {
        Spacer()
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("No Results")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("No ROMs found for \"\(searchText)\"")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Try it again with a different search term")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        Spacer()
    }

    @ViewBuilder
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                resultCountHeader

                let results = searchViewModel.searchResults
                ForEach(results) { rom in
                    SearchResultRow(rom: rom, isLast: rom.id == results.last?.id)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var resultCountHeader: some View {
        if !searchViewModel.searchResults.isEmpty {
            HStack {
                Text("\(searchViewModel.searchResults.count) Result(s) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
    }
}

private struct SearchResultRow: View {
    let rom: Rom
    let isLast: Bool

    var body: some View {
        NavigationLink(destination: RomDetailView(rom: rom)) {
            SearchRomRowView(rom: rom)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)

        if !isLast {
            Divider()
                .padding(.leading, 72)
        }
    }
}

#Preview {
    SearchView()
}
