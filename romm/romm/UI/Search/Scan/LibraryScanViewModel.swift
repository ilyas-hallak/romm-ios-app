//
//  LibraryScanViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation
import Observation

/// Holds the live scan task outside the main actor's isolation so `deinit` can
/// cancel it. Cancelling the task ends the event stream, which closes the
/// socket, and a socket left open keeps the server's scan session alive.
final class ScanTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func replace(with newTask: Task<Void, Never>?) {
        lock.lock()
        let previous = task
        task = newTask
        lock.unlock()
        previous?.cancel()
    }

    func cancel() {
        replace(with: nil)
    }
}

@Observable
@MainActor
class LibraryScanViewModel {
    /// How many ROMs of the live feed are kept, so memory stays flat on a scan
    /// that walks a library of tens of thousands of files.
    static let liveRomLimit = 200

    // Status, polled from /api/tasks/status
    var scan: LibraryScanStatus?
    var isLoading = false
    var errorMessage: String?

    // Start sheet
    var isShowingStartSheet = false
    var selectedScanType: LibraryScanType = .quick
    var platforms: [Platform] = []
    var selectedPlatformIds: Set<Int> = []
    var isLoadingPlatforms = false

    // Live scan
    var isStarting = false
    var isLive = false
    var isStopping = false
    var liveStats: LibraryScanStats?
    var currentPlatform: LibraryScanPlatform?
    var recentRoms: [LibraryScanRom] = []
    /// The server's own word on the run, e.g. that a scan is already going.
    var scanNotice: String?

    // Credentials prompt
    var isShowingCredentialsPrompt = false
    var credentialsNotice: String?

    private let getLatestLibraryScanUseCase: GetLatestLibraryScanUseCase
    private let startLibraryScanUseCase: StartLibraryScanUseCase
    private let stopLibraryScanUseCase: StopLibraryScanUseCase
    private let saveScanCredentialsUseCase: SaveScanCredentialsUseCase
    private let getPlatformsUseCase: GetPlatformsUseCase

    private var pollingTask: Task<Void, Never>?
    private let liveScanTask = ScanTaskHandle()

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.getLatestLibraryScanUseCase = factory.makeGetLatestLibraryScanUseCase()
        self.startLibraryScanUseCase = factory.makeStartLibraryScanUseCase()
        self.stopLibraryScanUseCase = factory.makeStopLibraryScanUseCase()
        self.saveScanCredentialsUseCase = factory.makeSaveScanCredentialsUseCase()
        self.getPlatformsUseCase = factory.makeGetPlatformsUseCase()
    }

    deinit {
        liveScanTask.cancel()
    }

    /// True while a scan is going, whether this app started it or not. The
    /// polled status covers a scan started in the web UI or before this session.
    var isScanRunning: Bool {
        if isLive { return true }
        guard let scan else { return false }
        return scan.state == .running || scan.state == .queued
    }

    // MARK: - Status

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

    /// Cancels polling and the live scan feed. Call from the sheet's
    /// onDisappear: the server keeps scanning, only this app stops listening.
    func cancelAllTasks() {
        pollingTask?.cancel()
        pollingTask = nil
        liveScanTask.cancel()
        isLive = false
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

    // MARK: - Start and stop

    func startScan() {
        guard !isStarting, !isLive else { return }
        isShowingStartSheet = false
        scanNotice = nil
        errorMessage = nil
        isStarting = true

        let type = selectedScanType
        let platformIds = selectedPlatformIds.sorted()

        Task {
            await runScan(type: type, platformIds: platformIds)
        }
    }

    func stopScan() {
        guard !isStopping else { return }
        isStopping = true

        Task {
            defer { isStopping = false }
            do {
                try await stopLibraryScanUseCase.execute()
            } catch let error as ScanAuthError {
                handle(authError: error)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Credentials

    func submitCredentials(username: String, password: String) {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else { return }

        do {
            try saveScanCredentialsUseCase.execute(username: trimmedUsername, password: password)
            isShowingCredentialsPrompt = false
            credentialsNotice = nil
            startScan()
        } catch {
            credentialsNotice = error.localizedDescription
        }
    }

    func dismissCredentialsPrompt() {
        isShowingCredentialsPrompt = false
        credentialsNotice = nil
    }

    // MARK: - Live feed

    private func runScan(type: LibraryScanType, platformIds: [Int]) async {
        do {
            let events = try await startLibraryScanUseCase.execute(type: type, platformIds: platformIds)
            isStarting = false
            beginLiveRun()

            liveScanTask.replace(with: Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    await self.apply(event: event)
                }
                guard let self else { return }
                await self.finishLiveRun()
            })
        } catch let error as ScanAuthError {
            isStarting = false
            handle(authError: error)
        } catch {
            isStarting = false
            errorMessage = error.localizedDescription
        }
    }

    private func beginLiveRun() {
        isLive = true
        liveStats = nil
        currentPlatform = nil
        recentRoms = []
        scanNotice = nil
    }

    private func apply(event: LibraryScanEvent) {
        switch event {
        case .platform(let platform):
            currentPlatform = platform
        case .rom(let rom):
            recentRoms.insert(rom, at: 0)
            if recentRoms.count > Self.liveRomLimit {
                recentRoms.removeLast(recentRoms.count - Self.liveRomLimit)
            }
        case .stats(let stats):
            liveStats = stats
        case .finished:
            scanNotice = "Scan finished."
            isLive = false
        case .failed(let reason):
            // "A scan is already in progress" arrives this way and is an
            // ordinary answer, not a crash.
            scanNotice = reason
            isLive = false
        }
    }

    private func finishLiveRun() async {
        isLive = false
        currentPlatform = nil
        await load()
    }

    private func handle(authError: ScanAuthError) {
        switch authError {
        case .credentialsRequired:
            credentialsNotice = nil
            isShowingCredentialsPrompt = true
        case .credentialsRejected:
            credentialsNotice = authError.errorDescription
            isShowingCredentialsPrompt = true
        case .serverNotConfigured, .sessionCookieMissing:
            errorMessage = authError.errorDescription
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
