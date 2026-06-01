# RomM iOS App

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)

A native iOS companion app for [RomM](https://github.com/rommapp/romm). Connect to your RomM server to browse, manage, and organize your retro game ROM collection directly from your iPhone or iPad.

## Download

### TestFlight Beta

Join the beta program and help improve the app:

[Join TestFlight Beta](https://testflight.apple.com/join/F4C5mhrC)

## Features

- 🎮 Browse and search your ROM library
- 📱 Native iOS design with dark mode
- 🖼️ View game covers, screenshots, and metadata
- 📊 Cards and table view layouts
- 📚 Organize games in collections
- 📈 Server statistics and platform insights
- 💾 Download and manage ROMs locally on your device
- 🔄 Transfer ROMs via SFTP to remote devices
- 📲 Basic iPad support (enhanced version coming soon)

## Screenshots

<p align="center">
  <img src="screenshots/iphone_1.png" width="200" alt="Screenshot 1" />
  <img src="screenshots/iphone_2.png" width="200" alt="Screenshot 2" />
  <img src="screenshots/iphone_3.png" width="200" alt="Screenshot 3" />
</p>

## Getting Started

This repository uses git submodules for the embedded emulator cores in `Vendor/` (DeltaCore, GBADeltaCore, GBCDeltaCore, NESDeltaCore, SNESDeltaCore, N64DeltaCore, MelonDSDeltaCore, GPGXDeltaCore). Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/ilyas-hallak/romm-ios-app.git
```

If you already cloned without submodules, initialize them afterwards:

```sh
git submodule update --init --recursive
```

Then open `romm/romm.xcodeproj` in Xcode and build.

## Contributing

1. Follow the established Clean Architecture patterns
2. Maintain one ViewModel per View (no sharing between views)
3. Use the existing dependency injection system
4. Follow SwiftUI best practices
5. Ensure proper error handling and logging

## License

This project is part of the RomM ecosystem for ROM management and organization.
