//
//  SearchViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation

@MainActor
@Observable
class SearchViewModel {
    var searchResults: [Rom] = []
    var isLoading = false
    var errorMessage: String?

    private let searchRomsUseCase: SearchRomsUseCase
    private var searchTask: Task<Void, Never>?

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.searchRomsUseCase = factory.makeSearchRomsUseCase()
    }

    // Debounced search – call from onChange
    func scheduleSearch(query: String) {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearResults()
            return
        }

        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            await execute(query: query)
        }
    }

    // Immediate search – call from onSubmit
    func search(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask = Task { await execute(query: trimmed) }
    }

    func cancelAllTasks() {
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
    }

    func clearError() {
        errorMessage = nil
    }

    func clearResults() {
        searchTask?.cancel()
        searchTask = nil
        searchResults = []
        errorMessage = nil
        isLoading = false
    }

    private func execute(query: String) async {
        isLoading = true
        errorMessage = nil
        defer {
            if !Task.isCancelled { isLoading = false }
        }

        do {
            let results = try await searchRomsUseCase.execute(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            do {
                let legacy = try await DefaultDependencyFactory.shared.romsRepository.searchRomsLegacy(query: query)
                guard !Task.isCancelled else { return }
                searchResults = legacy
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch let legacyError {
                guard !Task.isCancelled else { return }
                errorMessage = "Search failed: \(legacyError.localizedDescription)"
                searchResults = []
            }
        }
    }
}
