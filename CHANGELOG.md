# Changelog

All builds of the RomM iOS app, newest first.

## Version 1.0

### Build 50 (2026-08-31)

**New**
- PSP games now run on the device through the PPSSPP core.
- PlayStation games now rumble through a connected controller or device haptics.
The intensity can be adjusted in the in-game menu, and the setting is in Settings under Emulator.
- A Help screen is now reachable from Settings and from connection error messages.
It covers the most common questions and opens on the relevant answer automatically.
- RetroAchievements now show on the ROM detail page, including which ones you have already unlocked.
- A/B and X/Y can now be swapped for pads that use the Nintendo layout.
The switch is in Settings under Emulator and works in both the native and libretro engines.
- ROMs can be handed off to RetroArch or Delta instead of playing in the built-in emulator.
Set your preferred app in Settings under Emulator.
- A new RetroAchievements settings screen is available under Emulator in Settings.
You can view and change the linked RA username there, and sync your per-game progress manually.
Earned achievements now also show correctly in the ROM detail view.

**Fixed**
- The native engine's audio no longer stays silent after starting a game while another app was playing audio.
Affected cases: starting over a running podcast, resuming after a phone call or unplugging headphones.
- Connection error messages now say what actually went wrong, for example whether the address is unreachable, the server returned an unexpected response, or the URL points to something other than a RomM server.
Previously the app could show a raw HTML error page or a generic message that looked the same regardless of the cause.
- Buttons near the d-pad respond more reliably.
The d-pad was claiming any touch inside a 32pt margin around itself, so nearby buttons like Start and Select were sometimes swallowed.

**Known issues**
- PS1, PC Engine and Master System can still crash when audio resumes after a call, unplugged headphones, or coming back from the background.
- N64 can exit on its own in some games.
- With a physical controller you cannot reach the save and load menu yet.
- The heart in ROM lists stays empty with a physical controller.

### Build 49 (2026-08-22)

**New**
- Games now play with the ring switch on silent.
The ring switch no longer mutes the console, and the volume follows the hardware buttons like any other media app.
Affects GBA, SNES, NES, Game Boy, N64, Mega Drive and DS.
- Starting a game while music or a podcast is running works too.
The other app stops and the game takes over, instead of the game coming up silent.

**Fixed**
- RomM 5.2.0 no longer shows a false "unsupported server version" warning.

**Known issues**
- PS1, PC Engine and Master System can still crash when audio resumes after a call, unplugged headphones, or coming back from the background.
- N64 can exit on its own in some games.
- With a physical controller you cannot reach the save and load menu yet.
- The heart in ROM lists stays empty with a physical controller.

### Build 48 (2026-08-21)

**New**
- Controller skins: paste a .deltaskin link or a collection page like delta-skins.github.io and switch skins per system.
Native cores only, so GBA, SNES, NES, Game Boy, N64 and DS.

**Fixed**
- N64 save states were written incomplete and silently did nothing when loaded.
Please save your N64 states once more, the old ones cannot be recovered.
- Web emulator games no longer ask you to pick a save state, since it cannot restore them.
- The heart no longer lights up for every rated or currently playing game.
- Favouriting now works on servers where the favourites collection does not exist yet, it gets created for you.
- The RomM 5.x top bar stays hidden during emulation again.
- Leaving a game before it finished starting no longer crashes the app.

### Build 47 (2026-08-19)

**New**
- Play on TV: with an Apple TV or an HDMI adapter the game moves to the big screen on its own, while your phone stays the controller.
Works with both engines, so GBA, SNES, NES, Mega Drive, N64 and DS as well as PS1, PC Engine and the Sega cores.
- Physical controllers now work in the libretro cores too, so PS1, PC Engine and the Sega systems take a gamepad.
- Save games and save states sync with the RomM server through its own save-sync API on server 4.9 and newer.
- Battery saves can be exported, and .srm files are supported.

**Improved**
- The Play button is back on the ROM detail page.
- The Downloads tab shows a clearer unavailable state and a last-sync badge.
- The tab bar stays visible and minimizes as you scroll, and a downloaded ROM cover flies into the Downloads tab.
- The save-state menu pre-selects the slot you used last.

**Fixed**
- Save-state slots are numbered the same way in both menus.

### Builds 40 to 46 (June to August 2026)

These builds were released from a separate build worktree and have no individual build markers left in the repository, so they are summarised together.

The download queue arrived, with a download button on every ROM and downloads that keep running in the background.
Sign-in moved to the browser through a device flow, which also fixed a login loop.
Controller Mode lets you drag the game to where you want it and hides the touch controls.
Games can resume straight from a save state on launch.
The Devices and Downloads area was redesigned, covers load faster, and every list got its own search.
PC Engine, TurboGrafx-16 and Genesis Plus GX joined the emulator, and buttons give haptic feedback on release.
The app kept up with the RomM server API through 4.9, 5.0 and 5.1.

### Build 39 (2026-06-01)

**New**
- A Home tab shows recently added games, what you were playing last, and a breakdown by platform.
- Save games and save states are synced to the RomM server while you play.
- The app records when you last played a game, so the server stays in sync.
- A "Group ROMs" setting matches the grouping behaviour of the web interface.
- PS1 games can switch between 4:3 and 16:9 in the pause menu.

**Improved**
- Stronger haptics and larger touch areas for the on-screen controls.
- Deleting a downloaded ROM now asks for confirmation first.

**Fixed**
- PS1 memory cards are kept across sessions, and leaving a PS1 game no longer crashes.
- The search keyboard can be dismissed again.

### Build 25 (2026-05-27)

**New**
- Native emulator: GBA, SNES, NES, Game Boy, N64, Mega Drive and DS now use a dedicated on-device emulator engine with touch controls, landscape support, and a save-state menu.
- Rotating the device reloads the controller skin correctly.
- DS microphone permission is requested when needed.

**Fixed**
- Starting a game from a platform list works reliably.
- The save-state menu opens from the on-screen menu button.

### Build 23 (2026-05-16)

**New**
- Support for a native emulator engine is wired up internally, preparing GBA and other systems to move off the web emulator.
- The connection debug panel has a copy button to share diagnostics.

### Build 21 (2026-04-19)

**New**
- QR-code pairing: scan the code from your RomM profile page to sign in without a password.
The romm:// deep link also opens the pairing flow directly.
- Development server builds show a compatibility warning instead of blocking the app.
- RomM 4.8.0 and 4.8.1 are now supported.

**Fixed**
- Revoking a paired token on the server logs you out cleanly.
- Connection diagnostics correctly distinguish network errors from decoding errors.
- Username/password sign-in saves the right auth method.

### Build 15 (2026-02-14)

**New**
- The setup screen checks the server version and shows a connection log with expandable error details.
- Empty platforms are filtered from the list.

**Improved**
- The web emulator exit button is in English.
- Log-level picker in Settings uses a cleaner menu style.

### Build 13 (2026-01-06)

**New**
- Games that are not downloaded yet open in the built-in web emulator (EmulatorJS).
- Platform icons are shown in the library.
- Server statistics view with a per-platform breakdown.

**Fixed**
- ROM list no longer crashes when the server returns optional fields.

### Build 6 (2025-11-16)

**New**
- Local device ROM management: share or remove downloaded games.
- Skeleton loading states while the library is loading.

**Improved**
- Cover images load faster and no longer overflow on N64.
- Setup screen UX cleaned up, with a reset-configuration flow.

### Earlier builds

The app launched with browsing and searching your RomM library, downloading ROMs to the device, and playing them in the built-in emulator.
Supported systems include GBA, SNES, NES, Game Boy, N64, DS, Mega Drive, PS1, PC Engine and Master System.
Sign in either through your browser or with a username and password.
