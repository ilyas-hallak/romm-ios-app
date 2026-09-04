import Foundation
import UIKit

/// A ROM waiting on the pasteboard for the user to paste it in the target app.
struct PasteboardHandoffInfo: Identifiable, Equatable {
    let id = UUID()
    let romName: String
    let appName: String
}

/// Routes a Play tap to the external emulator app the user picked, from any
/// screen that offers Play.
///
/// This used to live inside `RomDetailViewModel`, which meant the ROM detail
/// screen was the only place the Play target was honoured: the downloads list
/// went straight to `LaunchEmulatorUseCase` and silently booted the built-in
/// engine instead. Since "where does Play send a game" is one user-level
/// setting, it has to be answered the same way everywhere, so it lives in one
/// object that every Play entry point drives.
///
/// Holds the presentation state for the handoff as well, because the two steps
/// are inseparable: iOS does not let us preselect a target, so the first launch
/// has to go through the system "Open in" menu and only later ones can deep link.
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
    /// Surfaced by the host screen; nil while nothing went wrong.
    var errorMessage: String?
    /// True while a ROM is being unpacked, hashed or handed over.
    var isLaunching: Bool = false

    /// The ROM currently being handed over.
    ///
    /// Held here rather than passed in by the caller because the confirmation
    /// arrives asynchronously from the system menu, long after the host screen
    /// has cleared its own "launching" state.
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

    /// Routes a Play tap to the configured external emulator.
    ///
    /// - Returns: false when the built-in emulator should take over instead, so a
    ///   caller can use this as a guard ahead of its own launch path.
    func play(romId: Int) async -> Bool {
        guard let targetID = playTarget.externalEmulatorID else { return false }
        let target = targetID.emulator

        guard externalAppLauncher.isInstalled(target) else {
            errorMessage = "\(target.displayName) is not installed. "
                + "Install it, or switch Play back to the built-in emulator in Settings."
            return true
        }

        guard let resolved = try? getDownloadedROMUseCase.execute(romId: romId) else {
            errorMessage = "Download this ROM before opening it in \(target.displayName)."
            return true
        }

        // Working out an identifier can mean unpacking an archive and hashing a
        // whole ROM, and copying a disc image out of the ROM folder is not
        // instant either, so the Play spinner covers everything below.
        isLaunching = true
        defer { isLaunching = false }
        await Task.yield()

        if handoffStore.hasHandedOff(romId: romId, to: targetID) {
            if let identifier = try? await gameIdentifier(for: resolved, emulator: target),
               await externalAppLauncher.launch(target, gameIdentifier: identifier) {
                logger.info("Launched ROM \(romId) in \(target.displayName)")
                markPlayed(romId: romId)
                return true
            }
            // The app turned the link down, so its library no longer holds the
            // ROM. Hand it over again rather than leaving Play dead.
            logger.info("\(target.displayName) rejected the deep link, handing the ROM over again")
            handoffStore.forget(romId: romId)
        }

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
        return true
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
    /// The temp copy is deliberately left behind: apps that open documents in
    /// place (RetroArch) still read from it while importing, and deleting it here
    /// would truncate the import. `GetROMShareFilesUseCase` collects old copies on
    /// the next share instead.
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
    /// The pasteboard keeps the ROM: the user may still paste it, and clearing it
    /// here would be the one thing that makes the handoff impossible.
    func dismissPasteboardHandoff() {
        pasteboardHandoff = nil
    }

    // MARK: - Private

    /// The identifier the target app will use, worked out once and then reused.
    ///
    /// Hashing a ROM on every Play tap would put seconds between the tap and the
    /// game, so the answer is cached the first time it is needed.
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
        // Which file goes over decides whether the target app accepts the import
        // and whether our identifier matches the one it derives, so it is worth
        // having in the log after the app switch has torn down any console.
        logger.info("Handing \(result.files.map { $0.lastPathComponent }.joined(separator: ", ")) "
            + "to \(targetDisplayName ?? "external app") "
            + "(unpacked=\(handoff.unpackedROMURL != nil), id=\(handoff.gameIdentifier))")
        // The "Open in" menu carries a single document. Multi-file ROMs such as
        // cue/bin need every part, so those go through the share sheet, which the
        // user then has to point at the emulator themselves.
        if result.files.count == 1, let url = result.files.first {
            // A target that cannot take a document from the "Open in" menu gets it
            // over the pasteboard instead. Multi-file ROMs stay on the share sheet
            // above: one pasteboard item cannot carry a set, and such a target has
            // no way to import one anyway.
            if playTarget.externalEmulatorID?.emulator.romDelivery == .pasteboard {
                handOverViaPasteboard(url: url, romName: rom.name)
                return
            }
            openInItem = OpenInItem(url: url, tempDirectory: result.tempDirectory)
        } else {
            shareItem = ShareURLsItem(urls: result.files, tempDirectory: result.tempDirectory)
        }
    }

    /// Puts the ROM on the general pasteboard, for apps that only import through
    /// an item provider.
    private func handOverViaPasteboard(url: URL, romName: String) {
        let appName = targetDisplayName ?? "the external emulator"
        guard let provider = NSItemProvider(contentsOf: url) else {
            errorMessage = "Could not put this ROM on the clipboard."
            return
        }
        UIPasteboard.general.itemProviders = [provider]
        logger.info("Put \(url.lastPathComponent) on the pasteboard for \(appName)")
        // The paste happens inside the other app, where nothing reports back, so
        // the ROM must not count as handed over: the next Play tap would deep link
        // into a library that may never have received it.
        handoffRomId = nil
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
