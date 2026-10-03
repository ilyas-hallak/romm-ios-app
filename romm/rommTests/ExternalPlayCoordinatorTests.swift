//
//  ExternalPlayCoordinatorTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

/// Backed by a real, unique temp directory, so tests that need the real hashing
/// pipeline (`ResolveExternalGameIdentifierUseCase` -> `ROMFileResolver` ->
/// `FileHashing`) can run it against an actual file instead of mocking it away.
private final class FakeLocalROMs: PLocalROMRepository, @unchecked Sendable {
    var roms: [DownloadedROM] = []
    let romsBaseURL: URL

    init() {
        romsBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalPlayCoordinator-\(UUID().uuidString)", isDirectory: true)
    }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { roms }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { roms.first { $0.id == id } }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { roms.count }

    /// Writes a real GBA ROM file under `romsBaseURL`, so the real resolver and
    /// hasher have something to read, and registers it as downloaded.
    func addRealGBARom(id: Int) -> DownloadedROM {
        let fileName = "Game \(id).gba"
        let directory = romsBaseURL.appendingPathComponent("gba/\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(repeating: 0xAB, count: 64).write(to: directory.appendingPathComponent(fileName))

        let rom = DownloadedROM(
            id: id, name: "Game \(id)", platformName: "GBA", platformSlug: "gba",
            downloadedAt: Date(), totalSizeBytes: 64, localDirectory: "gba/\(id)",
            files: [DownloadedROMFile(fileName: fileName, fileSizeBytes: 64)],
            urlCover: nil
        )
        roms.append(rom)
        return rom
    }

    /// Registers a downloaded ROM with no backing file, for tests that never
    /// reach the resolver because a cached identifier (or an earlier guard)
    /// short-circuits it.
    @discardableResult
    func addROM(id: Int) -> DownloadedROM {
        let rom = DownloadedROM(
            id: id, name: "Game \(id)", platformName: "GBA", platformSlug: "gba",
            downloadedAt: Date(), totalSizeBytes: 64, localDirectory: "gba/\(id)",
            files: [DownloadedROMFile(fileName: "Game \(id).gba", fileSizeBytes: 64)],
            urlCover: nil
        )
        roms.append(rom)
        return rom
    }
}

/// A successful deep link reports "last played" to the server, best effort.
/// `FakeAPIClient.updateRomLastPlayed` traps on that call, so this stands in
/// wherever a test takes that path.
private final class NoOpRomsRepository: PRomsRepository, @unchecked Sendable {
    private(set) var lastPlayedRomIds: [Int] = []

    func getRoms(platformId: Int?, searchTerm: String?, limit: Int, offset: Int, char: String?, orderBy: String?, orderDir: String?, collectionId: Int?) async throws -> PaginatedRomsResponse {
        fatalError("not used in these tests")
    }
    func getRomsWithFilters(platformId: Int?, searchTerm: String?, limit: Int, offset: Int, char: String?, orderBy: String?, orderDir: String?, collectionId: Int?, filters: RomFilters) async throws -> PaginatedRomsResponse {
        fatalError("not used in these tests")
    }
    func getRomDetails(id: Int) async throws -> RomDetails { fatalError("not used in these tests") }
    func toggleRomFavorite(romId: Int, isFavorite: Bool) async throws { fatalError("not used in these tests") }
    func isRomFavorite(romId: Int) async throws -> Bool { fatalError("not used in these tests") }
    func updateLastPlayed(romId: Int) async throws { lastPlayedRomIds.append(romId) }
    func searchRoms(query: String) async throws -> [Rom] { fatalError("not used in these tests") }
    func searchRomsLegacy(query: String) async throws -> [Rom] { fatalError("not used in these tests") }
}

@MainActor
struct ExternalPlayCoordinatorTests {

    private func makeCoordinator(
        localROMs: PLocalROMRepository,
        handoffStore: FakeHandoffStore,
        launcher: FakeExternalAppLauncher
    ) -> ExternalPlayCoordinator {
        let factory = MockDependencyFactory(
            romsRepository: NoOpRomsRepository(),
            localROMRepository: localROMs,
            externalEmulatorHandoffStore: handoffStore,
            externalAppLauncher: launcher
        )
        let coordinator = ExternalPlayCoordinator(factory: factory)
        coordinator.overrideTarget(.external(.manicEmu))
        return coordinator
    }

    /// Polls an observable condition instead of sleeping a fixed amount, since
    /// `confirmAlreadyInTarget()`/`copyToTargetAgain()` finish their work on a
    /// detached `Task` the test cannot await directly. Bounded, so a regression
    /// that never flips the condition fails the test instead of hanging it.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    // MARK: - play()

    @Test func playForAPasteboardTargetAlreadyCopiedOnceAsksBeforeRelaunching() async {
        let localROMs = FakeLocalROMs()
        localROMs.addROM(id: 1)
        let handoffStore = FakeHandoffStore()
        handoffStore.markCopiedToPasteboard(romId: 1, to: .manicEmu)
        let launcher = FakeExternalAppLauncher()
        let coordinator = makeCoordinator(localROMs: localROMs, handoffStore: handoffStore, launcher: launcher)

        let handled = await coordinator.play(romId: 1)

        #expect(handled)
        #expect(coordinator.relaunchConfirmation?.romId == 1)
        #expect(coordinator.relaunchConfirmation?.targetID == .manicEmu)
        #expect(launcher.launchedGameIdentifiers.isEmpty)
        #expect(coordinator.pasteboardHandoff == nil)
        #expect(coordinator.handoffRomId == nil)
    }

    @Test func playWhileLaunchingIsAlreadyInFlightDoesNothing() async {
        let localROMs = FakeLocalROMs()
        let handoffStore = FakeHandoffStore()
        let launcher = FakeExternalAppLauncher()
        let coordinator = makeCoordinator(localROMs: localROMs, handoffStore: handoffStore, launcher: launcher)
        coordinator.isLaunching = true

        let handled = await coordinator.play(romId: 99)

        #expect(handled)
        #expect(launcher.openCallCount == 0)
        #expect(launcher.launchedGameIdentifiers.isEmpty)
        #expect(coordinator.relaunchConfirmation == nil)
        #expect(coordinator.errorMessage == nil)
        #expect(handoffStore.handedOff.isEmpty)
    }

    // MARK: - confirmAlreadyInTarget()

    @Test func confirmAlreadyInTargetWithASuccessfulLaunchMarksHandedOffAndLaunches() async {
        let localROMs = FakeLocalROMs()
        localROMs.addROM(id: 1)
        let handoffStore = FakeHandoffStore()
        // Cached, so the launch resolves without needing a real ROM file on disk.
        handoffStore.cacheGameIdentifier("manic-id-1", romId: 1, kind: .manicGameID)
        let launcher = FakeExternalAppLauncher()
        launcher.launchResult = true
        let coordinator = makeCoordinator(localROMs: localROMs, handoffStore: handoffStore, launcher: launcher)
        coordinator.relaunchConfirmation = PasteboardRelaunchConfirmation(
            romId: 1, targetID: .manicEmu, appName: "Manic EMU"
        )

        coordinator.confirmAlreadyInTarget()

        #expect(coordinator.relaunchConfirmation == nil)
        #expect(handoffStore.handedOff.contains(1))
        await waitUntil { !coordinator.isLaunching }
        #expect(launcher.launchedGameIdentifiers == ["manic-id-1"])
        #expect(coordinator.errorMessage == nil)
        #expect(coordinator.pasteboardHandoff == nil)
    }

    @Test func confirmAlreadyInTargetWithARejectedLaunchForgetsAndHandsOverAgain() async {
        let localROMs = FakeLocalROMs()
        _ = localROMs.addRealGBARom(id: 2)
        let handoffStore = FakeHandoffStore()
        let launcher = FakeExternalAppLauncher()
        launcher.launchResult = false
        let coordinator = makeCoordinator(localROMs: localROMs, handoffStore: handoffStore, launcher: launcher)
        coordinator.relaunchConfirmation = PasteboardRelaunchConfirmation(
            romId: 2, targetID: .manicEmu, appName: "Manic EMU"
        )

        coordinator.confirmAlreadyInTarget()

        await waitUntil { coordinator.pasteboardHandoff != nil }
        // The failed deep link forgets the old handoff before starting a new
        // one, so the ROM ends up not handed off but copied to the pasteboard
        // again, which is the observable shape of "a new handover started".
        #expect(handoffStore.forgottenRomIds == [2])
        #expect(handoffStore.handedOff.contains(2) == false)
        #expect(handoffStore.pasteboardCopied.contains(2))
        #expect(coordinator.pasteboardHandoff != nil)
        #expect(coordinator.errorMessage == nil)
    }

    // MARK: - copyToTargetAgain()

    @Test func copyToTargetAgainSetsAnErrorWhenTheROMIsNoLongerDownloaded() {
        let localROMs = FakeLocalROMs()
        // No ROM registered: id 3 is not downloaded.
        let handoffStore = FakeHandoffStore()
        let launcher = FakeExternalAppLauncher()
        let coordinator = makeCoordinator(localROMs: localROMs, handoffStore: handoffStore, launcher: launcher)
        coordinator.relaunchConfirmation = PasteboardRelaunchConfirmation(
            romId: 3, targetID: .manicEmu, appName: "Manic EMU"
        )

        coordinator.copyToTargetAgain()

        #expect(coordinator.errorMessage == "Download this ROM before opening it in Manic EMU.")
        #expect(coordinator.relaunchConfirmation == nil)
        #expect(coordinator.isLaunching == false)
        #expect(handoffStore.forgottenRomIds.isEmpty)
    }

    @Test func copyToTargetAgainSetsTheNotInstalledErrorWhenTheTargetIsGone() {
        let localROMs = FakeLocalROMs()
        localROMs.addROM(id: 4)
        let handoffStore = FakeHandoffStore()
        let launcher = FakeExternalAppLauncher()
        launcher.installed = false
        let coordinator = makeCoordinator(localROMs: localROMs, handoffStore: handoffStore, launcher: launcher)
        coordinator.relaunchConfirmation = PasteboardRelaunchConfirmation(
            romId: 4, targetID: .manicEmu, appName: "Manic EMU"
        )

        coordinator.copyToTargetAgain()

        #expect(coordinator.errorMessage == "Manic EMU is not installed. "
            + "Install it, or switch Play back to the built-in emulator in Settings.")
        #expect(coordinator.relaunchConfirmation == nil)
        #expect(coordinator.isLaunching == false)
    }

    // MARK: - cancelRelaunchConfirmation()

    @Test func cancelRelaunchConfirmationOnlyClearsState() {
        let localROMs = FakeLocalROMs()
        localROMs.addROM(id: 5)
        let handoffStore = FakeHandoffStore()
        handoffStore.markCopiedToPasteboard(romId: 5, to: .manicEmu)
        let launcher = FakeExternalAppLauncher()
        let coordinator = makeCoordinator(localROMs: localROMs, handoffStore: handoffStore, launcher: launcher)
        coordinator.relaunchConfirmation = PasteboardRelaunchConfirmation(
            romId: 5, targetID: .manicEmu, appName: "Manic EMU"
        )

        coordinator.cancelRelaunchConfirmation()

        #expect(coordinator.relaunchConfirmation == nil)
        #expect(handoffStore.handedOff.isEmpty)
        #expect(handoffStore.forgottenRomIds.isEmpty)
        // Unchanged: cancelling must not touch what was already on the pasteboard.
        #expect(handoffStore.pasteboardCopied.contains(5))
        #expect(launcher.launchedGameIdentifiers.isEmpty)
        #expect(launcher.openCallCount == 0)
    }
}
