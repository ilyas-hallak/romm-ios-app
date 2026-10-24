# Delta core versions

The eight Delta submodules match the `Cores/` gitlinks in
[Delta commit 8d768919](https://github.com/rileytestut/Delta/tree/8d768919b1fb6bf99ec2899b6e8e0146a8268637/Cores),
the published **2.0 release, build 177**. Checked on October 24, 2026.

| Submodule | Pinned commit |
| --- | --- |
| DeltaCore | `869042a5699b19df3cf9f3369a950737ff818149` |
| GBADeltaCore | `af8531a09a0e811eff1e8703fd171e9645c45e26` |
| GBCDeltaCore | `0871ccaad2bbd7cbd2de0ce06f9e26dc3d1bfdde` |
| GPGXDeltaCore | `1825ade5359c69445690ee535ffbbeb11dcac2e3` |
| MelonDSDeltaCore | `0a8a09a9416ba1c28abf00d4639f155915fb3c49` |
| N64DeltaCore | `56aefef59d947edbf2eb34b0a0288d751b006f30` |
| NESDeltaCore | `c88ef1e7c68ad723194d1b691362ac7d7394f968` |
| SNESDeltaCore | `ed3a432616bfabaa376c554f7d352958e5bfb13b` |

All submodules use the official `rileytestut` repositories. The previous GBA and
SNES fork pins contain upstream commits only; no fork-specific changes were lost.
The release also updates ZIPFoundation to `24da6cff` and snes9x to `3ab93fc9`.
These include the upstream Xcode 27 compiler fixes, replacing the earlier local
SNES comparator patch. No local vendor source patches are needed.

## iPhone Duo port

RomM uses DeltaCore's released `.inner`, `.outer`, `.splitView`, and `.cover`
skin traits and the actual melonDS Duo artwork. The built-in skin owns the DS
screen geometry and stylus hit targets; RomM refreshes it when window traits
change, including same-orientation inner/outer transitions. Imported custom
skins retain their existing per-system selection and upstream fallback rules.

The app-level behavior is adapted from Delta's
[GameViewController](https://github.com/rileytestut/Delta/blob/8d768919b1fb6bf99ec2899b6e8e0146a8268637/Delta/Emulation/GameViewController.swift),
[CoverView](https://github.com/rileytestut/Delta/blob/8d768919b1fb6bf99ec2899b6e8e0146a8268637/Delta/Components/CoverView.swift),
and pause-menu reserved-region handling:

- Closing the hinge activates the DS lid input and presents supported cover artwork.
- DS games get one second to react before pausing; reopening cancels the delayed pause.
- Opening the hinge or dismissing the cover releases the lid and clears only the cover pause reason.
- Menu, scene, manual, and state-restore pauses remain independent.
- The cover follows the interface orientation, blocks gameplay touches, and provides an accessible Open console action.
- The save-state menu uses the trailing/bottom pane when iOS reports a division region.

The iOS 27.1 APIs are availability guarded; older devices keep their existing
layout and controls. Existing external-display rendering remains registered
while the phone's skin changes.

For complete runtime acceptance, check a DS game on both displays and orientations,
including stylus input, then close/reopen the device both normally and within
the one-second lid interval. Repeat with the pause menu open, after a background
trip, and with an external display connected. Unfolding must not dismiss a menu
or restart a game that is still paused for another reason.

## Native engine and touch controls

Select **Settings → Emulator → Play with → Native (DeltaCore, etc.)** to use the
embedded Delta cores. The web engine and external emulator apps use different
playback paths.

Fresh installs of the full, non-AppStore build default to Native, including
Debug builds. Missing or invalid engine preferences use the same default.
Native selects DeltaCore for supported systems and libretro for additional
platforms. Existing supported engine selections remain saved; an installation
previously set to Web must be switched to Native explicitly.

Touch controls hide automatically when GameController reports a connected
controller. This includes a simulator-forwarded **MFi/Gamepad**; the debug
Simulate connected controller switch does not need to be enabled for that
controller to be detected. Enable **Always show touch controls** in the
Controller section of Emulator settings, or in the native in-game menu, to keep
the touch skin visible alongside the controller. The preference persists and
updates the current session immediately. Screen size and drag-to-position
controls apply only while touch controls are hidden.

Native bitmap cores use Delta's Metal presentation option when running in the
Simulator, working around a crash in the Simulator's OpenGLES/CoreImage path.
This app-level workaround does not change the pinned vendor source, N64's
OpenGLES renderer, or the renderer chosen on physical devices. Game Boy playback
and touch Start, D-pad, and menu input were observed working on the iPhone Duo
simulator with this path. DS still presents black in the tested simulator
session. Runtime inspection found nonblack GPU buffers, enabled video output,
two game views, and a 256 × 384 image in the rendering path; the visible
presentation remains under investigation.

## Validation status

Evidence collected on October 24, 2026:

| Check | Confirmed result | Scope |
| --- | --- | --- |
| iPhone 18 Pro simulator, iOS 27.0, full `rommTests` | 1,089 tests in 147 suites passed; zero failures | Final native-default and touch-control override revision |
| iPad Pro 13-inch (M5) simulator, iOS 27.0, full `rommTests` | 1,089 tests in 147 suites passed; zero failures | Same final compiled suite, run with `test-without-building` |
| iPhone Duo simulator, iOS 27.1, focused checks | 20 test definitions in 5 suites passed; zero failures, including parameterized core/skin cases and pause-policy checks | Before the final preference-default-only change; native-default behavior is covered by the final iPhone/iPad suites |
| iPhone Duo simulator, iOS 27.1, final app build | Build succeeded; installed and relaunched | Final revision; persisted engine is Native and Always show touch controls is enabled |
| Real-service integration on iPhone and iPad simulators | Token-authenticated app services and read APIs passed on both | Read-only service evidence; not gameplay acceptance |
| Generic physical-device `romm` Release build, unsigned | Build succeeded | Final native-default and touch-control override revision |
| Generic physical-device `romm-AppStore` Release build, unsigned | Build succeeded | Final native-default and touch-control override revision |

The full regression suites include actual archives and image decoding for all
seven core skins across conventional iPhone and iPad layouts, DS screen crops
and touch hit regions, Duo skin fallback, and independent pause reasons. Those
automated skin/policy checks do not run a ROM. Local test results and summaries
are under the ignored `build/compatibility/` directory. The latest full-suite
bundles are `iphone18pro-native-default-regression.xcresult` and
`ipadpro13-native-default-regression.xcresult`, with matching
`*-native-default-summary.json` summaries. The focused Duo result is
`duo-touch-regression.xcresult` with `duo-touch-summary.json`.

DS gameplay acceptance is blocked by the black output. Stylus interaction with
a running DS game, hinge sleep/wake, inner/outer display transitions during
gameplay, and external-display coexistence still need runtime verification.
Unsigned device builds do not establish installation, physical-device gameplay,
signing, or distribution. The app retains its iOS 18.6 minimum, but an actual
iOS 18.6 runtime or device has not been exercised in this validation.

## Xcode 27.1 simulator build

Install Git LFS before initializing submodules. The DS and NES skin archives
contain LFS assets; pointer files compile but cannot render controller skins.
For an existing checkout, pull those assets before building:

```sh
git submodule update --init --recursive
git -C Vendor/MelonDSDeltaCore lfs install --local
git -C Vendor/MelonDSDeltaCore lfs pull
git -C Vendor/NESDeltaCore lfs install --local
git -C Vendor/NESDeltaCore lfs pull
xcodebuild -project romm/romm.xcodeproj -scheme romm \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' \
  -derivedDataPath build/ios27.1-iphone-duo/DerivedData \
  IPHONEOS_DEPLOYMENT_TARGET=18.6 build
```

The command-line deployment-target override also covers older nested projects
such as ZIPFoundation, while leaving the app's iOS 18.6 minimum unchanged.
The separate prebuilt Libretro cores contain device binaries. This simulator
build does not establish that those binaries can load, or that games, saves,
audio, controller skins, or Duo fold behavior work on a physical device.
