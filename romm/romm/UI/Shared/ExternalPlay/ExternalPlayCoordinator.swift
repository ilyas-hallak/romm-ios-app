import Foundation
import UIKit
import UniformTypeIdentifiers

/// A ROM waiting on the pasteboard for the user to paste it in the target app.
struct PasteboardHandoffInfo: Identifiable, Equatable {
    let id = UUID()
    let romName: String
    let appName: String
}

/// A ROM that already went to this target's pasteboard once, asking whether it
/// made it into the target's library or still needs copying again.
struct PasteboardRelaunchConfirmation: Identifiable, Equatable {
    let id = UUID()
    let romId: Int
    let targetID: ExternalEmulatorID
    let appName: String
}

/// Routes a Play tap to the external emulator app the user picked, from any
/// screen that offers Play.
///
/// Where Play sends a game is one app-wide setting, so it is answered in one
/// object that every Play entry point drives rather than per screen.
///
/// Holds the handoff's presentation state as well, because the two are
/// inseparable: iOS does not let us preselect a target, so the first launch goes
/// through the system "Open in" menu and only later ones can deep link.
@Observable
@MainActor
final class ExternalPlayCoordinator {

    /// Set when a single-file ROM should go through the system "Open in" menu.
    var openInItem: OpenInItem?
    /// Set when a multi-file ROM has to go through the share sheet instead.
    var shareItem: ShareURLsItem?
    /// Set when the ROM went onto the pasteboard and the user has to paste it in
    /// the target app.
    var pasteboardHandoff: PasteboardHandoffInfo?
    /// Set when a ROM already went to this target's pasteboard once, asking the
    /// user whether to deep link in or copy it over again.
    var relaunchConfirmation: PasteboardRelaunchConfirmation?
    /// Surfaced by the host screen; nil while nothing went wrong.
    var errorMessage: String?
    /// True while a ROM is being unpacked, hashed or handed over.
    var isLaunching: Bool = false

    /// The ROM currently being handed over.
    ///
    /// Held here because the menu's confirmation arrives long after the host
    /// screen has cleared its own "launching" state.
    private(set) var handoffRomId: Int?

    private(set) var playTarget: PlayTarget

    private let logger = Logger.emulator
    private let playTargetPreference: PPlayTargetPreference
    private let externalAppLauncher: PExternalAppLauncher
    private let getDownloadedROMUseCase: PGetDownloadedROMUseCase
    private let getROMShareFilesUseCase: PGetROMShareFilesUseCase
    private let handoffStore: PExternalEmulatorHandoffStore
    private let resolveExternalGameIdentifierUseCase: PResolveExternalGameIdentifierUseCase
    private let updateLastPlayedUseCase: PUpdateLastPlayedUseCase

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.playTargetPreference = factory.playTargetPreference
        self.externalAppLauncher = factory.externalAppLauncher
        self.getDownloadedROMUseCase = factory.makeGetDownloadedROMUseCase()
        self.getROMShareFilesUseCase = factory.makeGetROMShareFilesUseCase()
        self.handoffStore = factory.externalEmulatorHandoffStore
        self.resolveExternalGameIdentifierUseCase = factory.makeResolveExternalGameIdentifierUseCase()
        self.updateLastPlayedUseCase = factory.makeUpdateLastPlayedUseCase()
        self.playTarget = factory.playTargetPreference.current
    }

    /// True when Play hands the ROM to another app instead of emulating it here.
    var playsExternally: Bool { playTarget.externalEmulatorID != nil }

    /// The app Play currently points at, for labels and hints.
    var targetDisplayName: String? { playTarget.externalEmulatorID?.emulator.displayName }

    /// Re-reads the Play destination, e.g. after coming back from settings.
    func refreshPlayTarget() {
        playTarget = playTargetPreference.current
    }

    /// Points this coordinator at a target without changing the user's setting.
    ///
    /// For the setup assistant's test run, which hands a ROM to the app being
    /// set up before it becomes the saved target.
    func overrideTarget(_ target: PlayTarget) {
        playTarget = target
    }

    /// Routes a Play tap to the configured external emulator.
    ///
    /// - Returns: false when the built-in emulator should take over instead, so a
    ///   caller can use this as a guard ahead of its own launch path.
    func play(romId: Int) async -> Bool {
        guard let targetID = playTarget.externalEmulatorID else { return false }
        // A handoff is already in flight (possibly from a relaunch confirmation
        // whose host screen already cleared its own launching guard), so a
        // second tap must not run alongside it and clobber its state.
        guard !isLaunching else { return true }
        let target = targetID.emulator

        guard installedOrError(target) else { return true }
        guard let resolved = downloadedOrError(romId: romId, target: target) else { return true }

        // Unpacking, hashing and copying a disc image all take time, so the
        // Play spinner covers everything below.
        isLaunching = true
        defer { isLaunching = false }
        await Task.yield()

        switch ExternalPlayDecision.action(
            romId: romId, target: targetID, delivery: target.romDelivery, handoffStore: handoffStore
        ) {
        case .launchDirectly:
            await relaunch(romId: romId, resolved: resolved, target: target)

        case .confirmBeforeRelaunching:
            relaunchConfirmation = PasteboardRelaunchConfirmation(
                romId: romId, targetID: targetID, appName: target.displayName
            )

        case .handOver:
            await handOver(romId: romId, resolved: resolved, target: target)
        }
        return true
    }

    /// The user confirmed this ROM already made it into the target's library,
    /// so deep link straight in and remember it as handed off from now on.
    func confirmAlreadyInTarget() {
        guard let confirmation = relaunchConfirmation else { return }
        relaunchConfirmation = nil
        handoffStore.markHandedOff(romId: confirmation.romId, to: confirmation.targetID)
        let target = confirmation.targetID.emulator
        guard installedOrError(target) else { return }
        guard let resolved = downloadedOrError(romId: confirmation.romId, target: target) else { return }
        // Set synchronously, before the Task even gets scheduled, so a Play tap
        // landing in the gap before it runs sees the guard in `play()` and backs
        // off instead of running alongside this.
        isLaunching = true
        Task { [weak self] in
            defer { self?.isLaunching = false }
            await self?.relaunch(romId: confirmation.romId, resolved: resolved, target: target)
        }
    }

    /// The user said the ROM is not in the target yet, so copy it over again.
    func copyToTargetAgain() {
        guard let confirmation = relaunchConfirmation else { return }
        relaunchConfirmation = nil
        let target = confirmation.targetID.emulator
        guard installedOrError(target) else { return }
        guard let resolved = downloadedOrError(romId: confirmation.romId, target: target) else { return }
        isLaunching = true
        Task { [weak self] in
            defer { self?.isLaunching = false }
            await self?.handOver(romId: confirmation.romId, resolved: resolved, target: target)
        }
    }

    /// Dismisses the relaunch confirmation without doing anything.
    func cancelRelaunchConfirmation() {
        relaunchConfirmation = nil
    }

    /// Records that an "Open in" menu actually delivered the ROM, so the next Play
    /// tap can deep link instead of asking again.
    func handoffDidComplete(receivingBundleIdentifier: String) {
        guard let romId = handoffRomId, let targetID = playTarget.externalEmulatorID else { return }
        let target = targetID.emulator
        guard target.matches(bundleIdentifier: receivingBundleIdentifier) else {
            logger.info("ROM \(romId) went to \(receivingBundleIdentifier), not \(target.displayName), not remembered")
            return
        }
        handoffStore.markHandedOff(romId: romId, to: targetID)
        markPlayed(romId: romId)
    }

    /// No installed app claims this file type, so the "Open in" menu stayed empty.
    func handoffFoundNoTargets() {
        let name = targetDisplayName ?? "the external emulator"
        errorMessage = "No app on this device can open this ROM. "
            + "Make sure \(name) is installed and supports this file type."
        openInItem = nil
    }

    /// Dismisses the share sheet.
    ///
    /// The temp copy is left behind: apps that open documents in place still
    /// read from it while importing, so deleting it here truncates the import.
    /// `GetROMShareFilesUseCase` collects old copies on the next share.
    func cleanupShareTemp() {
        shareItem = nil
    }

    /// Sends the user to the target app to finish a pasteboard handoff there.
    func openPasteboardTarget() {
        pasteboardHandoff = nil
        guard let target = playTarget.externalEmulatorID?.emulator else { return }
        Task { [externalAppLauncher] in
            _ = await externalAppLauncher.open(target)
        }
    }

    /// Dismisses the pasteboard hint.
    ///
    /// The pasteboard keeps the ROM, since the user may still paste it.
    func dismissPasteboardHandoff() {
        pasteboardHandoff = nil
    }

    // MARK: - Private

    /// Whether the target app is installed, surfacing the standard error when
    /// it is not.
    private func installedOrError(_ target: any PExternalEmulator) -> Bool {
        guard externalAppLauncher.isInstalled(target) else {
            errorMessage = "\(target.displayName) is not installed. "
                + "Install it, or switch Play back to the built-in emulator in Settings."
            return false
        }
        return true
    }

    /// The ROM resolved from local storage, or nil with the "download it
    /// first" error set.
    private func downloadedOrError(romId: Int, target: any PExternalEmulator) -> ResolvedDownloadedROM? {
        guard let resolved = try? getDownloadedROMUseCase.execute(romId: romId) else {
            errorMessage = "Download this ROM before opening it in \(target.displayName)."
            return nil
        }
        return resolved
    }

    /// Deep links a ROM already believed to be in the target's library,
    /// handing it over again if the target turns the link down.
    private func relaunch(romId: Int, resolved: ResolvedDownloadedROM, target: any PExternalEmulator) async {
        if await launchDirectly(romId: romId, resolved: resolved, target: target) { return }
        // The app turned the link down, so its library no longer holds the
        // ROM. Hand it over again rather than leaving Play dead.
        handoffStore.forget(romId: romId)
        await handOver(romId: romId, resolved: resolved, target: target)
    }

    /// Deep links a ROM already believed to be in the target's library.
    private func launchDirectly(
        romId: Int,
        resolved: ResolvedDownloadedROM,
        target: any PExternalEmulator
    ) async -> Bool {
        guard let identifier = try? await gameIdentifier(for: resolved, emulator: target),
              await externalAppLauncher.launch(target, gameIdentifier: identifier) else {
            logger.info("\(target.displayName) rejected the deep link, handing the ROM over again")
            return false
        }
        logger.info("Launched ROM \(romId) in \(target.displayName)")
        markPlayed(romId: romId)
        return true
    }

    /// Hands a ROM over to the target app for the first time, or again after a
    /// rejected deep link or an unconfirmed pasteboard copy.
    private func handOver(
        romId: Int,
        resolved: ResolvedDownloadedROM,
        target: any PExternalEmulator
    ) async {
        do {
            let handoff = try await resolveExternalGameIdentifierUseCase.execute(
                rom: resolved.rom,
                baseURL: resolved.baseURL,
                emulator: target
            )
            handoffStore.cacheGameIdentifier(
                handoff.gameIdentifier,
                romId: romId,
                kind: target.identifierKind
            )
            handoffRomId = romId
            presentHandoff(of: resolved.rom, using: handoff)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The identifier the target app will use, cached because hashing a ROM on
    /// every Play tap would put seconds between the tap and the game.
    private func gameIdentifier(
        for resolved: ResolvedDownloadedROM,
        emulator: any PExternalEmulator
    ) async throws -> String {
        if let cached = handoffStore.cachedGameIdentifier(
            romId: resolved.rom.id,
            kind: emulator.identifierKind
        ) {
            return cached
        }
        let handoff = try await resolveExternalGameIdentifierUseCase.execute(
            rom: resolved.rom,
            baseURL: resolved.baseURL,
            emulator: emulator
        )
        handoffStore.cacheGameIdentifier(
            handoff.gameIdentifier,
            romId: resolved.rom.id,
            kind: emulator.identifierKind
        )
        return handoff.gameIdentifier
    }

    private func presentHandoff(of rom: DownloadedROM, using handoff: ExternalGameHandoff) {
        // An emulator that identifies a game by its content has to receive
        // exactly the file that was hashed, so an unpacked ROM goes over on its
        // own rather than inside the archive it came from.
        let result = handoff.unpackedROMURL.map { getROMShareFilesUseCase.execute(fileAt: $0) }
            ?? getROMShareFilesUseCase.execute(rom: rom)

        guard !result.files.isEmpty else {
            errorMessage = "No files available to open."
            return
        }
        // Logged, because which file goes over decides whether the import is
        // accepted, and the app switch tears down any attached console.
        logger.info("Handing \(result.files.map { $0.lastPathComponent }.joined(separator: ", ")) "
            + "to \(targetDisplayName ?? "external app") "
            + "(unpacked=\(handoff.unpackedROMURL != nil), id=\(handoff.gameIdentifier))")
        // The "Open in" menu carries a single document. Multi-file ROMs such as
        // cue/bin need every part, so those go through the share sheet, which the
        // user then has to point at the emulator themselves.
        if result.files.count == 1, let url = result.files.first {
            // A target that cannot take a document from the menu gets it over
            // the pasteboard. Multi-file ROMs stay on the share sheet, since one
            // pasteboard item cannot carry a set.
            if let targetID = playTarget.externalEmulatorID, targetID.emulator.romDelivery == .pasteboard {
                handOverViaPasteboard(url: url, romId: rom.id, romName: rom.name, targetID: targetID)
                return
            }
            openInItem = OpenInItem(url: url, tempDirectory: result.tempDirectory)
        } else {
            shareItem = ShareURLsItem(urls: result.files, tempDirectory: result.tempDirectory)
        }
    }

    /// Puts the ROM on the general pasteboard, for apps that only import through
    /// an item provider.
    private func handOverViaPasteboard(url: URL, romId: Int, romName: String, targetID: ExternalEmulatorID) {
        let appName = targetDisplayName ?? "the external emulator"
        // The bytes go on themselves. A provider built from a file URL registers
        // public.file-url plus a promise, and neither survives: the URL points
        // into this app's container, and the promise needs this process alive.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            errorMessage = "Could not put this ROM on the clipboard."
            return
        }
        // Exactly one type, the one the extension resolves to. A broad type such
        // as public.data can hurt: an importer matching by substring may settle
        // on it and then find no extension to name the file after.
        let romType = UTType(filenameExtension: url.pathExtension) ?? .data
        // Eager, because a registered representation is produced on request, and
        // by then this process may be suspended with nobody left to answer.
        let provider = NSItemProvider(item: data as NSData, typeIdentifier: romType.identifier)
        // The importer needs a name and appends the extension its type declares,
        // so this goes on without one to avoid landing as "Game.gba.gba".
        provider.suggestedName = url.deletingPathExtension().lastPathComponent
        UIPasteboard.general.itemProviders = [provider]
        logger.info("Put \(url.lastPathComponent) (\(data.count) bytes) on the pasteboard "
            + "for \(appName) (type=\(romType.identifier), name=\(provider.suggestedName ?? "-"))")
        // Nothing reports back from the other app, so this must not count as a
        // confirmed handoff, or the next Play tap deep links into an empty
        // library. It is remembered as a weaker "went over once" instead, so
        // the next Play tap asks rather than copying over silently again.
        handoffRomId = nil
        handoffStore.markCopiedToPasteboard(romId: romId, to: targetID)
        pasteboardHandoff = PasteboardHandoffInfo(romName: romName, appName: appName)
    }

    /// Reports the ROM as played to the server, best effort.
    private func markPlayed(romId: Int) {
        Task { [updateLastPlayedUseCase, logger] in
            do {
                try await updateLastPlayedUseCase.execute(romId: romId)
            } catch {
                logger.warning("Failed to update last_played for ROM \(romId): \(error)")
            }
        }
    }
}
