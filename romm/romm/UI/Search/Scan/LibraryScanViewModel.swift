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
    // Status, polled from /api/tasks/status
    var scan: LibraryScanStatus?
    var isLoading = false
    var errorMessage: String?
    /// False for a permission error: retrying would fail identically until the
    /// account reconnects, so the error view skips the dead-end Retry button.
    var canRetryError = true

    // Start sheet
    var isShowingStartSheet = false
    var selectedScanType: LibraryScanType = .quick
    var platforms: [Platform] = []
    var selectedPlatformIds: Set<Int> = []
    var isLoadingPlatforms = false

    var isStarting = false
    /// The server's own word on why a scan could not start, e.g. that one is
    /// already running.
    var scanNotice: String?

    private let getLatestLibraryScanUseCase: GetLatestLibraryScanUseCase
    private let startLibraryScanUseCase: StartLibraryScanUseCase
    private let getPlatformsUseCase: GetPlatformsUseCase

    private var pollingTask: Task<Void, Never>?

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getLatestLibraryScanUseCase = factory.makeGetLatestLibraryScanUseCase()
        self.startLibraryScanUseCase = factory.makeStartLibraryScanUseCase()
        self.getPlatformsUseCase = factory.makeGetPlatformsUseCase()
    }

    /// True while a scan is going, whether this app started it or not. The
    /// polled status covers a scan started in the web UI or before this session.
    var isScanRunning: Bool {
        guard let scan else { return false }
        return scan.state == .running || scan.state == .queued
    }

    // MARK: - Status

    /// Loads the latest scan once, then starts polling if it is still running.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        canRetryError = true

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
                canRetryError = !(error is LibraryScanAccessError)
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

    /// Cancels polling. Call from the sheet's onDisappear: the server keeps
    /// scanning, only this app stops asking about it.
    func cancelAllTasks() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Start sheet

    func showStartSheet() {
        scanNotice = nil
        isShowingStartSheet = true
        Task {
            await loadPlatforms()
        }
    }

    func loadPlatforms() async {
        guard platforms.isEmpty, !isLoadingPlatforms else { return }
        isLoadingPlatforms = true
        defer { isLoadingPlatforms = false }

        do {
            platforms = try await getPlatformsUseCase.execute()
        } catch {
            // The picker falls back to the whole library, which is the default
            // anyway, so a failed platform list is not worth an error banner.
            platforms = []
        }
    }

    func togglePlatform(_ platform: Platform) {
        if selectedPlatformIds.contains(platform.id) {
            selectedPlatformIds.remove(platform.id)
        } else {
            selectedPlatformIds.insert(platform.id)
        }
    }

    func selectAllPlatforms() {
        selectedPlatformIds.removeAll()
    }

    // MARK: - Start

    func startScan() {
        guard !isStarting, !isScanRunning else { return }
        isShowingStartSheet = false
        scanNotice = nil
        errorMessage = nil
        canRetryError = true
        isStarting = true

        let type = selectedScanType
        let platformIds = selectedPlatformIds.sorted()

        Task {
            await runScan(type: type, platformIds: platformIds)
        }
    }

    private func runScan(type: LibraryScanType, platformIds: [Int]) async {
        do {
            try await startLibraryScanUseCase.execute(type: type, platformIds: platformIds)
            isStarting = false
            await load()
        } catch let error as ScanStartError {
            isStarting = false
            if case .refused(let message) = error {
                scanNotice = message
            }
            await load()
        } catch {
            isStarting = false
            errorMessage = error.localizedDescription
            canRetryError = !(error is LibraryScanAccessError)
        }
    }

    // MARK: - Polling

    private func refreshPolling() {
        guard let scan, scan.state == .queued || scan.state == .running else {
            pollingTask?.cancel()
            pollingTask = nil
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
                pollingTask?.cancel()
                pollingTask = nil
            }
        } catch {
            // A single failed poll should not surface as an error while a scan
            // is still believed to be running, the next tick tries again.
        }
    }
}
