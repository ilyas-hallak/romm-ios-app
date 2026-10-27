# SFTP Integration Feature

## Overview

The SFTP feature allows users to connect directly to their ROM server via SFTP protocol to browse, preview, and download ROM files directly to their iOS device. This provides an alternative method to access ROMs beyond the standard RomM API.

## Use Cases

### Primary Use Case
- **Direct ROM Access**: Browse and download ROMs directly from the server's filesystem via SFTP
- **Offline ROM Management**: Download ROMs to device storage for offline access
- **Server File Exploration**: Navigate the server's directory structure to find and organize ROM files

### Secondary Use Cases
- **ROM Verification**: Check file integrity and sizes before download
- **Selective Downloading**: Choose specific ROM files without full collection sync
- **Remote File Management**: Basic file operations on the ROM server

## User Stories

1. **As a user**, I want to configure SFTP connection settings so that I can connect to my ROM server
2. **As a user**, I want to browse the server's directory structure so that I can find specific ROM files
3. **As a user**, I want to preview file information (size, date, type) before downloading
4. **As a user**, I want to download ROM files to my device for offline access
5. **As a user**, I want to manage downloaded ROM files on my device
6. **As a user**, I want the app to remember my SFTP connection settings securely

## Technical Requirements

### Core Functionality
- SFTP protocol implementation for iOS
- Secure credential storage using iOS Keychain
- File browser interface with directory navigation
- File download with progress indication
- Local file management and organization
- Connection state management and error handling

### Security Requirements
- Encrypted credential storage
- Secure SFTP connections (SSH key or password authentication)
- Certificate validation and host key verification
- Automatic connection timeout and cleanup

### Performance Requirements
- Efficient directory listing with lazy loading
- Resumable file downloads
- Background download support
- Bandwidth optimization for mobile connections

## User Interface Design

### SFTP Configuration View
```
┌─────────────────────────────────┐
│ SFTP Configuration              │
├─────────────────────────────────┤
│ Host: [________________]        │
│ Port: [22___]                   │
│ Username: [____________]        │
│ Password: [____________]        │
│ □ Use SSH Key                   │
│                                 │
│ [Test Connection] [Save]        │
└─────────────────────────────────┘
```

### File Browser View
```
┌─────────────────────────────────┐
│ < /home/user/roms              │
├─────────────────────────────────┤
│ 📁 nintendo/                   │
│ 📁 sega/                       │
│ 📁 playstation/                │
│ 🎮 game.rom         2.3 MB     │
│ 🎮 another.iso    145.7 MB     │
│                                 │
│ [↓ Download Selected]           │
└─────────────────────────────────┘
```

### Download Progress View
```
┌─────────────────────────────────┐
│ Downloading: game.rom           │
├─────────────────────────────────┤
│ [████████░░] 80% (1.8/2.3 MB)   │
│                                 │
│ Speed: 2.1 MB/s                 │
│ ETA: 3 seconds                  │
│                                 │
│ [Pause] [Cancel]               │
└─────────────────────────────────┘
```

## Architecture Design

### Data Layer
```
SFTPService
├── Connection Management
├── Authentication
├── File Operations
└── Error Handling

SFTPRepository
├── Connection Configuration
├── File Listing
├── Download Management
└── Local Storage
```

### Domain Layer
```
SFTPConnection (Model)
├── host: String
├── port: Int
├── username: String
├── authenticationType: AuthType
└── isConnected: Bool

RemoteFile (Model)
├── name: String
├── path: String
├── size: Int64
├── modifiedDate: Date
├── isDirectory: Bool
└── permissions: String

DownloadTask (Model)
├── file: RemoteFile
├── localURL: URL
├── progress: Double
├── status: DownloadStatus
└── error: Error?
```

### Presentation Layer
```
SFTPConfigurationView + ViewModel
├── Connection Settings Form
├── Connection Testing
├── Credential Management
└── Security Options

SFTPFileBrowserView + ViewModel
├── Directory Navigation
├── File Listing
├── File Selection
└── Download Initiation

DownloadManagerView + ViewModel
├── Active Downloads
├── Progress Monitoring
├── Download Control
└── Error Handling
```

## Implementation Plan

### Phase 1: Core SFTP Infrastructure
1. **SFTP Library Integration**
   - Use mft as the SFTP library, behind the app's own `SFTPClient` protocol
   - Create SFTP service wrapper
   - Implement basic connection management

2. **Security Layer**
   - Keychain integration for credential storage
   - SSL/TLS certificate handling
   - Host key verification

### Phase 2: File Operations
1. **Remote File Browser**
   - Directory listing implementation
   - File metadata extraction
   - Navigation stack management

2. **Download System**
   - File download with progress tracking
   - Resumable downloads
   - Background download support

### Phase 3: User Interface
1. **Configuration UI**
   - SFTP settings form
   - Connection testing interface
   - Credential management

2. **File Browser UI**
   - SwiftUI file browser
   - Directory navigation
   - File selection and actions

### Phase 4: Integration & Polish
1. **App Integration**
   - Settings integration
   - Tab bar addition
   - Deep linking support

2. **Error Handling & Polish**
   - Comprehensive error handling
   - Loading states
   - Connection recovery

## Dependencies

### External Libraries
- **mft** (github.com/mplpl/mft): SFTP client framework, LGPL-2.1.
  It bundles libssh (LGPL-2.1) and OpenSSL (Apache-2.0).
  The app ships it as a dynamic framework, and Settings > Licenses lists all three.

### SFTP client boundary
`SFTPService` only talks to the `SFTPClient` protocol (`Data/Services/SFTPClient.swift`).
`MFTSFTPClient` is the only type that imports mft, and `DependencyFactory` decides which client the service gets.
Swapping the library, for example for one under a permissive license, means writing a new adapter for that protocol and changing that one line in the factory.

### iOS Frameworks
- **Network**: Network connectivity monitoring
- **Security**: Keychain and certificate management
- **Foundation**: File system operations

## Testing Strategy

### Unit Tests
- SFTP connection management
- File operations and parsing
- Credential storage and retrieval
- Error handling scenarios

### Integration Tests
- End-to-end SFTP workflows
- Download functionality
- UI navigation flows

### Manual Testing
- Various SFTP server configurations
- Network interruption scenarios
- Large file downloads
- Security and authentication edge cases

## Future Enhancements

### Version 2.0
- **Bidirectional Sync**: Upload ROMs from device to server
- **Folder Synchronization**: Automatic sync with selected server directories
- **Advanced File Operations**: Move, delete, rename files on server
- **Multiple Server Support**: Connect to multiple SFTP servers
- **ROM Metadata Integration**: Combine SFTP files with RomM API metadata

### Version 3.0
- **Cloud Storage Integration**: Support for additional protocols (FTP, WebDAV, cloud services)
- **Advanced Search**: Server-side file search capabilities
- **Bandwidth Management**: Smart downloading based on network conditions
- **Collaborative Features**: Shared server access with other users