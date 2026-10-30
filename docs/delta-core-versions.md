# Delta core versions

The eight Delta submodules match the `Cores/` gitlinks in
[Delta commit 8d768919](https://github.com/rileytestut/Delta/tree/8d768919b1fb6bf99ec2899b6e8e0146a8268637/Cores),
the published **2.0 release, build 177**.

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

RomM's hinge coordinator and cover/menu presentation use UIKit and SwiftUI.
The pinned cores supply the controller artwork and screen mappings.

- Closing the hinge activates the DS lid input and presents supported cover artwork.
- DS games get one second to react before pausing; reopening cancels the delayed pause.
- Opening the hinge or dismissing the cover releases the lid and clears only the cover pause reason.
- Menu, scene, manual, and state-restore pauses remain independent.
- The cover follows the interface orientation, blocks gameplay touches, and provides an accessible Open console action.
- The save-state menu uses iOS division-region information to choose a display pane.

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
Debug builds. On upgrade, installations with existing setup or update-state
preferences and no engine selection retain their previous Web default. This
choice is persisted before onboarding or update checks write new preferences.
Explicit selections remain saved; invalid values use the Native fallback.
Native selects DeltaCore for supported systems and libretro for additional
platforms. A stored Web choice is only coerced when Web is unavailable in that
build.

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
OpenGLES renderer, or the renderer chosen on physical devices.

Build/test results, prior simulator checks, and pending device testing are
recorded in [PR #228](https://github.com/ilyas-hallak/romm-ios-app/pull/228).

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
