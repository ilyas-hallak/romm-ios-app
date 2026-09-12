//
//  LibraryScanViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation
import Observation

@Observable
@MainActor
class LibraryScanViewModel {
    var scan: LibraryScanStatus?
    var isLoading = false
    var errorMessage: String?

    private let getLatestLibraryScanUseCase: GetLatestLibraryScanUseCase
    private var pollingTask: Task<Void, Never>?

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getLatestLibraryScanUseCase = factory.makeGetLatestLibraryScanUseCase()
    }

    /// Loads the latest scan once, then starts polling if it is still running.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let latestScan = try await getLatestLibraryScanUseCase.execute()
            try Task.checkCancellation()
            scan = latestScan
            isLoading = false
            refreshPolling()
        } catch {
            if !Task.isCancelled {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func retry() {
        Task {
            await load()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Cancels the polling task. Call from the sheet's onDisappear so nothing
    /// keeps hitting the API once the scan status is no longer on screen.
    func cancelAllTasks() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refreshPolling() {
        guard let scan, scan.state == .queued || scan.state == .running else {
            cancelAllTasks()
            return
        }
        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.pollOnce()
            }
        }
    }

    private func pollOnce() async {
        do {
            let latestScan = try await getLatestLibraryScanUseCase.execute()
            guard !Task.isCancelled else { return }
            scan = latestScan
            if let scan, scan.state != .queued && scan.state != .running {
                cancelAllTasks()
            }
        } catch {
            // A single failed poll should not surface as an error while a scan
            // is still believed to be running, the next tick tries again.
        }
    }
}
