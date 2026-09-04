import SwiftUI

struct SFTPUploadView: View {
    @State private var viewModel: SFTPUploadViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeviceManagement = false

    let onPlayAfterDownload: ((Rom) -> Void)?
    let onShowInDownloads: (() -> Void)?

    init(
        rom: Rom,
        autoStartLocalDownload: Bool = false,
        onPlayAfterDownload: ((Rom) -> Void)? = nil,
        onShowInDownloads: (() -> Void)? = nil,
        factory: PDependencyFactory = DefaultDependencyFactory.shared
    ) {
        self._viewModel = State(initialValue: factory.makeSFTPUploadViewModel(rom: rom, autoStartLocalDownload: autoStartLocalDownload))
        self.onPlayAfterDownload = onPlayAfterDownload
        self.onShowInDownloads = onShowInDownloads
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if viewModel.isCompleted {
                    completedView
                } else if viewModel.isUploading || viewModel.isPreparing {
                    uploadingView
                } else {
                    configurationView
                }
            }
            .padding()
            .task {
                await viewModel.triggerAutoStartIfNeeded()
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isUploading || viewModel.isPreparing)
                }
                
                if !viewModel.isUploading && !viewModel.isPreparing && !viewModel.isCompleted {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(viewModel.isLocalDeviceSelected ? "Download" : "Upload") {
                            Task {
                                await viewModel.startUpload()
                            }
                        }
                        .disabled(!viewModel.canUpload || viewModel.isCheckingDuplicates)
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("Try Again") {
                    viewModel.resetUpload()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error ?? "")
            }
            .sheet(isPresented: $viewModel.showingDirectoryBrowser) {
                if let connection = viewModel.selectedConnection {
                    SFTPDirectoryBrowserView(connection: connection, romName: viewModel.rom.name) { path in
                        viewModel.selectTargetPath(path)
                    }
                }
            }
            .sheet(isPresented: $showingDeviceManagement) {
                NavigationView {
                    SFTPDevicesView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingDeviceManagement = false
                                }
                            }
                        }
                }
            }
        }
    }
    
    private var configurationView: some View {
        VStack(spacing: 24) {
            // ROM Info - Enhanced with specific variant details
            VStack(alignment: .leading, spacing: 8) {
                Text("ROM")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Show specific file name if available, fallback to name
                    Text(viewModel.rom.fileName ?? viewModel.rom.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        // ROM ID for debugging
                        Text("ID: \(viewModel.rom.id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // ROM size if available
                        if let sizeBytes = viewModel.rom.sizeBytes {
                            Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Show general ROM name as subtitle if fileName is different
                    if let fileName = viewModel.rom.fileName, fileName != viewModel.rom.name {
                        Text(viewModel.rom.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            
            // File Selection (only show if multiple files available)
            if viewModel.availableFiles.count > 1 {
                Divider()
                fileSelectionView
                Divider()
            }
            
            // Device Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Device")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                    // Local Device (This iPhone/iPad)
                    LocalDeviceSelectionRow(
                        isSelected: viewModel.isLocalDeviceSelected,
                        onSelect: { viewModel.selectLocalDevice() }
                    )

                    // SFTP Devices
                    ForEach(viewModel.connections) { connection in
                        DeviceSelectionRow(
                            connection: connection,
                            isSelected: viewModel.selectedConnection?.id == connection.id,
                            onSelect: { viewModel.selectConnection(connection) }
                        )
                    }

                    // Add Device Button
                    Button {
                        showingDeviceManagement = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Remote Device")
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Target Path Selection (only for SFTP devices)
            if viewModel.selectedConnection != nil && !viewModel.isLocalDeviceSelected {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Target Directory")
                        .font(.headline)

                    Button(action: viewModel.browseDirectories) {
                        HStack {
                            Image(systemName: "folder")
                            Text(viewModel.targetPath ?? "Choose directory...")
                                .foregroundColor(viewModel.targetPath != nil ? .primary : .secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Duplicate Files Warning (only for SFTP devices)
            if viewModel.hasDuplicateWarnings && !viewModel.isLocalDeviceSelected {
                duplicateWarningsSection
            }
            
            // Storage Warning
            if let storageWarning = viewModel.storageWarning {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(storageWarning)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
    }
    
    private var uploadingView: some View {
        VStack(spacing: 24) {
            // Progress Indicator
            VStack(spacing: 16) {
                let iconName = viewModel.isPreparing ? "arrow.down.circle" : (viewModel.isLocalDeviceSelected ? "arrow.down.circle" : "icloud.and.arrow.up")
                Image(systemName: iconName)
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                let fileCount = viewModel.totalFiles
                let actionText = viewModel.isLocalDeviceSelected ? "Downloading" : "Uploading"
                Text(viewModel.isPreparing ?
                     (fileCount > 1 ? "Preparing \(fileCount) files..." : "Preparing ROM...") :
                     (fileCount > 1 ? "\(actionText) \(fileCount) files..." : "\(actionText) ROM..."))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                VStack(spacing: 4) {
                    Text(viewModel.rom.fileName ?? viewModel.rom.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    if let fileName = viewModel.rom.fileName, fileName != viewModel.rom.name {
                        Text(viewModel.rom.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Text("ROM ID: \(viewModel.rom.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Progress Bar
            VStack(spacing: 8) {
                let progress = viewModel.isPreparing ? viewModel.prepareProgress : viewModel.uploadProgress
                
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                Text(viewModel.isPreparing ? viewModel.prepareMessage : viewModel.uploadProgressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private var completedView: some View {
        if viewModel.isLocalDeviceSelected {
            return AnyView(localDownloadCompletedView)
        } else {
            return AnyView(sftpUploadCompletedView)
        }
    }

    private var localDownloadCompletedView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            // Cover with success badge
            ZStack(alignment: .bottomTrailing) {
                CachedKFImage(urlString: viewModel.rom.urlCover) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "gamecontroller")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.7))
                        )
                }
                .frame(width: 160, height: 215)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color(.systemBackground)).frame(width: 38, height: 38))
                    .offset(x: 8, y: 8)
            }

            VStack(spacing: 6) {
                Text("Download Complete")
                    .font(.title3.bold())

                Text(viewModel.rom.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                let formatter = ByteCountFormatter()
                Text(formatter.string(fromByteCount: viewModel.totalBytes) + " · \(viewModel.totalFiles) file\(viewModel.totalFiles == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: {
                    let rom = viewModel.rom
                    dismiss()
                    onPlayAfterDownload?(rom)
                }) {
                    Label("Play", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.green)
                        )
                        .foregroundColor(.white)
                }

                Button(action: {
                    dismiss()
                    onShowInDownloads?()
                }) {
                    Label("View in Downloads", systemImage: "tray.full")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundColor(.accentColor)
                }

                Button("Back") {
                    dismiss()
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
    }

    private var sftpUploadCompletedView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("Upload Complete!")
                    .font(.title2)
                    .fontWeight(.semibold)

                let fileCount = viewModel.totalFiles
                Text(fileCount > 1 ? "All \(fileCount) files have been successfully transferred to the device." : "Your ROM has been successfully transferred to the device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ROM:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.rom.fileName ?? viewModel.rom.name)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Device:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.selectedConnection?.name ?? "Unknown")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Location:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.targetPath ?? "Unknown")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            HStack(spacing: 16) {
                Button("Send Another") {
                    viewModel.resetUpload()
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)

            Spacer()
        }
        .padding()
    }
    
    private var fileSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Files to Upload")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Select All") {
                        viewModel.selectAllFiles()
                    }
                    .font(.caption)
                    .disabled(viewModel.isLoadingFiles)
                    
                    Button("Deselect All") {
                        viewModel.deselectAllFiles()
                    }
                    .font(.caption)
                    .disabled(viewModel.isLoadingFiles)
                }
            }
            
            if viewModel.isLoadingFiles {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading files...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if viewModel.availableFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.questionmark")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No files found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.availableFiles) { fileInfo in
                        FileSelectionRow(
                            fileInfo: fileInfo,
                            isSelected: viewModel.selectedFiles.contains(fileInfo.id),
                            onToggle: { viewModel.toggleFileSelection(fileInfo.id) }
                        )
                    }
                }
            }
            
            if !viewModel.selectedFilesList.isEmpty {
                HStack {
                    Text("Selected: \(viewModel.selectedFiles.count) file(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    let totalSize = viewModel.selectedFilesList.reduce(0) { $0 + $1.fileSizeBytes }
                    Text("Total: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    @ViewBuilder
    private var duplicateWarningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicate Files Detected")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Text("The following files already exist on the server:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if viewModel.isCheckingDuplicates {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            VStack(spacing: 8) {
                ForEach(Array(viewModel.duplicateWarnings.values), id: \.id) { duplicateInfo in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: duplicateInfo.sizeMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(duplicateInfo.sizeMatch ? .green : .red)
                            .font(.caption)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(duplicateInfo.fileName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text(duplicateInfo.warningMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(duplicateInfo.sizeMatch ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                
                Text("Files with matching size and name will be skipped. Different sizes indicate potential overwrites.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

struct FileSelectionRow: View {
    let fileInfo: RomFileInfo
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileInfo.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(fileInfo.displaySize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !fileInfo.fileExtension.isEmpty {
                            Text(fileInfo.fileExtension.uppercased())
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct LocalDeviceSelectionRow: View {
    let isSelected: Bool
    let onSelect: () -> Void

    @MainActor
    private var deviceName: String {
        LocalDeviceManager.shared.currentDevice.name
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(deviceName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("(This Device)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Download to local storage")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DeviceSelectionRow: View {
    let connection: SFTPConnection
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(connection.connectionString)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SFTPUploadView(
        rom: Rom(
            id: 1,
            name: "Super Mario Bros.",
            platformId: 1,
            urlCover: nil,
            isFavourite: false,
            hasRetroAchievements: true,
            isPlayable: true
        ),
        factory: DefaultDependencyFactory.shared
    )
}
