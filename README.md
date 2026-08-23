# RomM iOS App

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)

A native iOS companion app for [RomM](https://github.com/rommapp/romm). Connect to your self-hosted RomM server to browse, play, and manage your retro game ROM collection directly from your iPhone or iPad.

**Compatible with RomM 5.0.***

## Download

### TestFlight Beta

Join the beta program and help improve the app:

[Join TestFlight Beta](https://testflight.apple.com/join/F4C5mhrC)

## Screenshots

<p align="center">
  <img src="screenshots/final/00-play-ingame.png" width="180" alt="Play games directly in the app" />
  <img src="screenshots/final/01-play-anywhere.png" width="180" alt="Take your retro library anywhere" />
  <img src="screenshots/final/03-browse-platform.png" width="180" alt="Browse your collection by platform" />
  <img src="screenshots/final/05-organize-collections.png" width="180" alt="Organize with collections" />
  <img src="screenshots/final/04-download-offline.png" width="180" alt="Download games for offline play" />
  <img src="screenshots/final/02-sync-saves.png" width="180" alt="Sync saves with your RomM instance" />
</p>

## Features

### Emulation
- 🎮 Play ROMs directly on your iPhone or iPad
- 🕹️ Native Delta emulator cores for GBA, GBC, GB, NES, SNES, N64, and NDS
- 🖥️ Libretro-based emulation for Sega Genesis/Mega Drive, Master System, Game Gear, Saturn, Dreamcast, PlayStation, PSP, and Arcade
- ☁️ Cloud save sync — upload and download save states and save files to/from your RomM server
- 🎛️ Physical controller support
- ⏩ 2x fast-forward for native DeltaCore emulation from the in-game menu

### Library
- 📱 Native SwiftUI design with dark mode support
- 🖼️ Game covers, screenshots, and full metadata from your RomM server
- 📊 Card and list view layouts
- 🔍 Search across your entire ROM library
- 📚 Browse by platform with ROM counts and platform logos
- 📁 Organize games in custom collections
- 📈 Server statistics and platform insights
- ⚙️ QR code scanner for quick server setup

### Offline & Transfer
- 💾 Download ROMs for offline play
- 🔄 Transfer ROMs to remote devices via SFTP
- 🗂️ BIOS file management for emulator cores

### Platform
- 📲 iPhone and iPad support

## Getting Started

This repository uses git submodules for the emulator cores in `Vendor/`. Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/ilyas-hallak/romm-ios-app.git
```

If you already cloned without submodules:

```sh
git submodule update --init --recursive
```

Then open `romm/romm.xcodeproj` in Xcode and build.

## Credits

> *Standing on the shoulders of giants.*

This app would not be possible without the outstanding open-source emulation work of:

- **[Delta / DeltaCore](https://github.com/rileytestut/DeltaCore)** by [Riley Testut](https://github.com/rileytestut) — the emulation framework powering GB, GBC, GBA, NES, SNES, N64, and NDS
- **[PCSX ReARMed](https://github.com/libretro/pcsx_rearmed)** via [Libretro](https://www.libretro.com) — PlayStation emulation on ARM

## Contributing

1. Follow the established Clean Architecture patterns (Domain / Data / UI layers)
2. Maintain one ViewModel per View — no sharing between views
3. Use Cases must not call other Use Cases — compose at the ViewModel level
4. Use the existing dependency injection system
5. Follow SwiftUI best practices
6. All user-facing strings must be in English

## License

MIT — see [LICENSE](LICENSE) for details. This project is part of the RomM ecosystem.
