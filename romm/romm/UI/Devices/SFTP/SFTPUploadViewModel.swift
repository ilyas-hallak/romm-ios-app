import Foundation
import Observation

struct DuplicateFileInfo: Identifiable {
    let id = UUID()
    let fileName: String
    let existingSize: Int64
    let newSize: Int64
    let remotePath: String
    
    var sizeMatch: Bool {
        existingSize == newSize
    }
    
    var warningMessage: String {
        if sizeMatch {
            return "File '\(fileName)' already exists with same size (\(ByteCountFormatter.string(fromByteCount: existingSize, countStyle: .file)))"
        } else {
            return "File '\(fileName)' already exists but with different size (existing: \(ByteCountFormatter.string(fromByteCount: existingSize, countStyle: .file)), new: \(ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file)))"
        }
    }
}

struct RomFileInfo: Identifiable, Hashable {
    let id: String
    let fileName: String
    let fileSizeBytes: Int64
    let fileExtension: String
    
    init(from romFile: RomFileSchema) {
        self.id = romFile.fileName
        self.fileName = romFile.fileName
        self.fileSizeBytes = Int64(romFile.fileSizeBytes)
        // Extract file extension from fileName
        self.fileExtension = (romFile.fileName as NSString).pathExtension
    }
    
    init(id: String, fileName: String, fileSizeBytes: Int64, fileExtension: String) {
        self.id = id
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.fileExtension = fileExtension
    }
    
    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

@MainActor
@Observable
class SFTPUploadViewModel {
    var connections: [SFTPConnection] = []
    var selectedConnection: SFTPConnection?
    var isLocalDeviceSelected = false
    var targetPath: String?
    var isUploading = false
    var uploadProgress: Double = 0.0
    var uploadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    private var _error: String?
    var error: String? {
        get {
            // Don't show errors if upload was successful
            return isUploadSuccessful ? nil : _error
        }
        set {
            if isUploadSuccessful && newValue != nil {
                print("⚠️ SFTP Upload: Ignoring error after successful completion: \(newValue ?? "unknown")")
                return
            }
            _error = newValue
        }
    }
    var isCompleted = false
    private var isUploadSuccessful = false
    var showingDirectoryBrowser = false
    
    // Preparation progress
    var isPreparing = false
    var prepareProgress: Double = 0.0
    var preparedBytes: Int64 = 0
    var prepareMessage = "Preparing ROM file..."
    
    // Multi-file support
    var availableFiles: [RomFileInfo] = []
    var selectedFiles: Set<String> = []
    var isLoadingFiles = false
    var currentFileIndex = 0
    var totalFiles = 0
    
    // Duplicate detection
    var isCheckingDuplicates = false
    var duplicateWarnings: [String: DuplicateFileInfo] = [:] // fileName -> DuplicateInfo
    var hasDuplicateWarnings: Bool {
        !duplicateWarnings.isEmpty
    }
    
    let rom: Rom
    let autoStartLocalDownload: Bool
    private(set) var didAutoStart: Bool = false
    private let getAllConnectionsUseCase: GetAllConnectionsUseCase
    private let manageDefaultConnectionUseCase: ManageDefaultConnectionUseCase
    private let uploadFileUseCase: UploadFileUseCase
    private let listDirectoryUseCase: ListDirectoryUseCase
    private let apiClient: PRommAPIClient

    init(
        rom: Rom,
        autoStartLocalDownload: Bool = false,
        factory: PDependencyFactory = DefaultDependencyFactory.shared
    ) {
        self.autoStartLocalDownload = autoStartLocalDownload
        print("🔍 Debug: SFTPUploadViewModel init with ROM:")
        print("🔍 Debug: ROM ID: \(rom.id)")
        print("🔍 Debug: ROM name: \(rom.name)")
        print("🔍 Debug: ROM slug: \(rom.slug)")
        print("🔍 Debug: ROM fileName: \(rom.fileName ?? "nil")")
        print("🔍 Debug: ROM platformId: \(rom.platformId)")
        print("🔍 Debug: ROM sizeBytes: \(rom.sizeBytes ?? 0)")

        self.rom = rom
        self.getAllConnectionsUseCase = factory.makeGetAllConnectionsUseCase()
        self.manageDefaultConnectionUseCase = factory.makeManageDefaultConnectionUseCase()
        self.uploadFileUseCase = factory.makeUploadFileUseCase()
        self.listDirectoryUseCase = factory.makeListDirectoryUseCase()
        self.apiClient = factory.apiClient


        loadConnections()
        loadAvailableFiles()
    }
    
    private func loadConnections() {
        connections = getAllConnectionsUseCase.execute()
        isLocalDeviceSelected = true
        selectedConnection = nil
    }

    /// Starts a local download automatically if requested at init and not yet started.
    /// Waits until at least one file is selected (loadAvailableFiles runs async).
    func triggerAutoStartIfNeeded() async {
        guard autoStartLocalDownload, !didAutoStart else { return }

        // Wait briefly for available files to load, then proceed.
        var waited = 0
        while availableFiles.isEmpty && waited < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waited += 1
        }

        guard !didAutoStart, autoStartLocalDownload, !selectedFiles.isEmpty else { return }
        didAutoStart = true
        await startUpload()
    }
    
    private func loadAvailableFiles() {
        Task {
            print("🔍 Debug: Loading available files for ROM ID: \(rom.id)")
            print("🔍 Debug: ROM name: \(rom.name)")
            print("🔍 Debug: ROM fileName: \(rom.fileName ?? "nil")")
            
            isLoadingFiles = true
            error = nil
            
            do {
                print("🔍 Debug: Calling getRomDetails API for ROM ID: \(rom.id)")
                // Use getRomDetails to get all files for this ROM
                let romDetails = try await apiClient.getRomDetails(id: rom.id)
                
                print("🔍 Debug: Successfully got ROM details")
                print("🔍 Debug: ROM details name: \(romDetails.name)")
                print("🔍 Debug: ROM details files count: \(romDetails.files.count)")

                var files: [RomFileInfo] = []
                if !romDetails.fsName.isEmpty {
                    let mainFile = RomFileInfo(
                        id: romDetails.fsName,
                        fileName: romDetails.fsName,
                        fileSizeBytes: Int64(romDetails.fsSizeBytes),
                        fileExtension: (romDetails.fsName as NSString).pathExtension
                    )
                    files.append(mainFile)
                    print("🔍 Debug: Main ROM file: \(romDetails.fsName)")
                }
                for supplementary in romDetails.files {
                    if supplementary.fileName != romDetails.fsName && !supplementary.fileName.isEmpty {
                        files.append(RomFileInfo(from: supplementary))
                    }
                }

                for (index, file) in files.enumerated() {
                    print("🔍 Debug: File \(index): \(file.fileName) (\(file.fileSizeBytes) bytes)")
                }

                await MainActor.run {
                    self.availableFiles = files

                    // Auto-select the first file by default
                    if let firstFile = files.first {
                        print("🔍 Debug: Auto-selecting first file: \(firstFile.fileName)")
                        self.selectedFiles = [firstFile.id]
                    }
                    
                    self.isLoadingFiles = false
                }
                
            } catch {
                print("❌ Debug: Failed to load ROM details: \(error)")
                print("❌ Debug: Error type: \(type(of: error))")
                if let localizedError = error as? LocalizedError {
                    print("❌ Debug: Error description: \(localizedError.errorDescription ?? "no description")")
                }
                
                await MainActor.run {
                    // Fallback to single file from ROM data
                    let fallbackFileName = rom.fileName ?? "\(rom.name).rom"
                    print("🔍 Debug: Using fallback file name: \(fallbackFileName)")
                    
                    let fallbackFile = RomFileInfo(
                        id: fallbackFileName,
                        fileName: fallbackFileName,
                        fileSizeBytes: Int64(rom.sizeBytes ?? 0),
                        fileExtension: (fallbackFileName as NSString).pathExtension
                    )
                    
                    print("🔍 Debug: Fallback file created: \(fallbackFile.fileName) (\(fallbackFile.fileSizeBytes) bytes)")
                    
                    self.availableFiles = [fallbackFile]
                    self.selectedFiles = [fallbackFile.id]
                    self.isLoadingFiles = false
                    
                    print("⚠️ Could not load ROM files, using fallback: \(error)")
                }
            }
        }
    }
    
    func selectConnection(_ connection: SFTPConnection) {
        selectedConnection = connection
        isLocalDeviceSelected = false
        targetPath = nil
    }

    func selectLocalDevice() {
        isLocalDeviceSelected = true
        selectedConnection = nil
        targetPath = nil
    }
    
    func browseDirectories() {
        guard selectedConnection != nil else { return }
        showingDirectoryBrowser = true
    }
    
    func selectTargetPath(_ path: String) {
        targetPath = path
        showingDirectoryBrowser = false
        
        // Check for duplicates whenever target path changes
        Task {
            await checkForDuplicates()
        }
    }
    
    // MARK: - Multi-File Selection
    
    func toggleFileSelection(_ fileId: String) {
        if selectedFiles.contains(fileId) {
            selectedFiles.remove(fileId)
        } else {
            selectedFiles.insert(fileId)
        }
        
        // Re-check duplicates when file selection changes
        Task {
            await checkForDuplicates()
        }
    }
    
    func selectAllFiles() {
        selectedFiles = Set(availableFiles.map { $0.id })
        Task {
            await checkForDuplicates()
        }
    }
    
    func deselectAllFiles() {
        selectedFiles.removeAll()
        Task {
            await checkForDuplicates()
        }
    }
    
    var selectedFilesList: [RomFileInfo] {
        return availableFiles.filter { selectedFiles.contains($0.id) }
    }
    
    func startUpload() async {
        // Route to local download or SFTP upload based on selection
        if isLocalDeviceSelected {
            await startLocalDownload()
            return
        }

        guard let connection = selectedConnection,
              let targetPath = targetPath,
              !isUploading else { return }
        
        isUploading = true
        uploadProgress = 0.0
        uploadedBytes = 0
        error = nil
        isCompleted = false
        
        // Get selected files to upload
        let filesToUpload = selectedFilesList
        guard !filesToUpload.isEmpty else {
            print("❌ SFTP Upload: No files selected")
            self.error = "No files selected for upload"
            isUploading = false
            return
        }
        
        totalFiles = filesToUpload.count
        currentFileIndex = 0
        
        // Calculate total size for progress tracking
        totalBytes = filesToUpload.reduce(0) { $0 + $1.fileSizeBytes }
        
        print("🔍 SFTP Upload: Starting upload of \(totalFiles) files (total: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)))")
        
        var localPaths: [String] = []
        var overallUploadedBytes: Int64 = 0
        
        do {
            // Upload each selected file
            for (index, fileInfo) in filesToUpload.enumerated() {
                currentFileIndex = index
                print("🔍 SFTP Upload: Processing file \(index + 1)/\(totalFiles): \(fileInfo.fileName)")
                
                // Download file
                let localPath = try await downloadRomFile(fileInfo: fileInfo)
                localPaths.append(localPath)
                
                // Validate downloaded file
                try await validateDownloadedFile(at: localPath, fileInfo: fileInfo)
                
                let fileSize = try getFileSize(at: localPath)
                let remotePath = targetPath.hasSuffix("/") ? "\(targetPath)\(fileInfo.fileName)" : "\(targetPath)/\(fileInfo.fileName)"
                
                // Upload file with progress tracking
                try await uploadFileUseCase.execute(
                    from: localPath,
                    to: remotePath,
                    connection: connection,
                    progressHandler: { [weak self] uploaded, total in
                        DispatchQueue.main.async {
                            guard let strongSelf = self, !strongSelf.isCompleted else { 
                                return 
                            }
                            
                            // Calculate overall progress across all files
                            let currentFileProgress = overallUploadedBytes + uploaded
                            let overallProgress = strongSelf.totalBytes > 0 ? Double(currentFileProgress) / Double(strongSelf.totalBytes) : 0.0
                            
                            strongSelf.uploadedBytes = currentFileProgress
                            
                            // Apply tolerance for progress calculation (SFTP often reports slightly less due to buffering)
                            let tolerantProgress = min(max(overallProgress, 0.0), 1.0)
                            
                            // If we're very close to completion (>98%) and uploaded is close to total, show 100%
                            if overallProgress > 0.98 && (total - uploaded) < 1024 * 1024 { // Within 1MB tolerance
                                strongSelf.uploadProgress = 1.0
                                print("🔍 Progress: File \(index + 1)/\(strongSelf.totalFiles) - 100% (tolerance applied)")
                            } else {
                                strongSelf.uploadProgress = tolerantProgress
                                print("🔍 Progress: File \(index + 1)/\(strongSelf.totalFiles) - \(Int(tolerantProgress * 100))% overall")
                            }
                        }
                    }
                )
                
                overallUploadedBytes += fileSize
                print("✅ SFTP Upload: File \(index + 1)/\(totalFiles) completed: \(fileInfo.fileName)")
            }
            
            // All uploads successful
            print("✅ SFTP Upload: All \(totalFiles) files uploaded successfully")
            isUploadSuccessful = true
            isCompleted = true
            uploadProgress = 1.0
            uploadedBytes = totalBytes
            error = nil
            
        } catch {
            print("❌ SFTP Upload: Upload failed with error: \(error)")
            self.error = error.localizedDescription
        }
        
        isUploading = false
        
        // Cleanup all temporary files
        for localPath in localPaths {
            do {
                try cleanupTemporaryFile(at: localPath)
                print("🔍 SFTP Upload: Cleaned up temporary file: \(localPath)")
            } catch {
                print("⚠️ SFTP Upload: Failed to cleanup temporary file: \(error)")
            }
        }
    }
    
    private func startLocalDownload() async {
        guard !isUploading else { return }

        isUploading = true
        uploadProgress = 0.0
        uploadedBytes = 0
        error = nil
        isCompleted = false

        // Get selected files to download
        let filesToDownload = selectedFilesList
        guard !filesToDownload.isEmpty else {
            print("❌ Local Download: No files selected")
            self.error = "No files selected for download"
            isUploading = false
            return
        }

        totalFiles = filesToDownload.count
        totalBytes = filesToDownload.reduce(0) { $0 + $1.fileSizeBytes }

        print("🔍 Local Download: Starting download of \(totalFiles) files (total: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)))")

        do {
            // Create LocalROMDownloadService
            let downloadService = LocalROMDownloadService(apiClient: apiClient)

            // Download ROM files to local storage
            let _ = try await downloadService.downloadROM(
                rom: rom,
                files: filesToDownload,
                progressHandler: { [weak self] downloadedBytes, totalBytes in
                    DispatchQueue.main.async {
                        guard let strongSelf = self, !strongSelf.isCompleted else {
                            return
                        }

                        let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0.0
                        strongSelf.uploadProgress = min(max(progress, 0.0), 1.0)
                        strongSelf.uploadedBytes = downloadedBytes

                        print("🔍 Local Download Progress: \(Int(progress * 100))%")
                    }
                }
            )

            // Download successful
            print("✅ Local Download: All files downloaded successfully")
            isUploadSuccessful = true
            isCompleted = true
            uploadProgress = 1.0
            uploadedBytes = totalBytes
            error = nil

        } catch {
            print("❌ Local Download: Download failed with error: \(error)")
            self.error = error.localizedDescription
        }

        isUploading = false
    }

    func resetUpload() {
        print("🔍 SFTP Upload: Resetting upload state")
        isUploading = false
        uploadProgress = 0.0
        uploadedBytes = 0
        totalBytes = 0
        isUploadSuccessful = false // Reset success flag first
        error = nil
        isCompleted = false
        currentFileIndex = 0
        totalFiles = 0
        selectedFiles.removeAll()
        targetPath = nil
        showingDirectoryBrowser = false
        
        // Reset preparation state
        isPreparing = false
        prepareProgress = 0.0
        preparedBytes = 0
        prepareMessage = "Preparing ROM file..."
    }
    
    private func downloadRomFile(fileInfo: RomFileInfo) async throws -> String {
        let localPath = getTemporaryFilePath(for: fileInfo.fileName)
        
        print("🔍 Debug: Starting ROM file download: \(fileInfo.fileName)")
        
        isPreparing = true
        prepareProgress = 0.0
        preparedBytes = 0
        prepareMessage = "Downloading \(fileInfo.fileName)..."
        
        defer {
            isPreparing = false
        }
        
        // Check available storage before download
        try checkStorageCapacity()

        let encodedFileName = encodePathComponent(fileInfo.fileName)
        let path = "api/roms/\(rom.id)/content/\(encodedFileName)"

        do {
            let tempURL = try await apiClient.downloadFile(path: path) { [weak self] downloadedBytes, totalBytes in
                Task { @MainActor in
                    guard let self = self, self.isPreparing else { return }

                    self.preparedBytes = downloadedBytes

                    if totalBytes > 0 {
                        let progress = min(max(Double(downloadedBytes) / Double(totalBytes), 0.0), 1.0)
                        self.prepareProgress = progress

                        if progress < 0.1 {
                            self.prepareMessage = "Connecting to server..."
                        } else if progress < 1.0 {
                            self.prepareMessage = "Downloading ROM file... \(Int(progress * 100))%"
                        } else {
                            self.prepareMessage = "Processing file..."
                        }
                    } else {
                        self.prepareMessage = "Downloading ROM file..."
                    }
                }
            }

            let destinationURL = URL(fileURLWithPath: localPath)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            let downloadedSize = try getFileSize(at: localPath)
            guard downloadedSize > 0 else {
                throw SFTPError.fileValidationFailed("Downloaded file is empty")
            }

            print("✅ Debug: ROM file saved successfully (\(downloadedSize) bytes)")
            return localPath

        } catch let apiError as APIClientError {
            let mappedError = mapDownloadError(apiError)
            print("❌ Debug: API client download error: \(apiError)")
            throw mappedError
        } catch {
            print("❌ Debug: Download error: \(error)")
            throw SFTPError.networkError(error.localizedDescription)
        }
    }

    private func encodePathComponent(_ value: String) -> String {
        var allowedCharacterSet = CharacterSet.urlPathAllowed
        allowedCharacterSet.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? value
    }

    private func mapDownloadError(_ error: APIClientError) -> SFTPError {
        switch error {
        case .authenticationRequired, .noCredentials:
            return .authenticationFailed
        case .noConfiguration:
            return .networkError("No server URL configured")
        case .invalidURL(let url):
            return .networkError("Invalid download URL: \(url)")
        case .networkError(let networkError):
            return .networkError(networkError.localizedDescription)
        case .invalidResponse(let statusCode, _):
            if statusCode == 404 {
                return .pathNotFound
            }
            if statusCode == 401 || statusCode == 403 {
                return .authenticationFailed
            }
            return .networkError("HTTP \(statusCode)")
        case .decodingError:
            return .downloadFailed
        case .cloudflareProtection(_):
            return .connectionFailed
        }
    }
    
    private func checkStorageCapacity() throws {
        print("🔍 Debug: Checking storage capacity...")
        
        // Get ROM size from details or estimate
        let requiredBytes: Int64
        
        // Try to get accurate file size from selected files
        if !selectedFilesList.isEmpty {
            requiredBytes = selectedFilesList.reduce(0) { $0 + $1.fileSizeBytes }
        } else {
            // Use estimation for now - could be improved with async ROM details fetching
            requiredBytes = estimateRomSize()
            print("⚠️ Using ROM size estimate: \(ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file))")
        }
        
        // Check available storage using use cases
        if !checkAvailableStorage(requiredBytes: requiredBytes) {
            let availableBytes = getAvailableStorageCapacity() ?? 0
            let requiredBytesWithBuffer = Int64(Double(requiredBytes) * 1.2)
            throw SFTPError.insufficientStorage(required: requiredBytesWithBuffer, available: availableBytes)
        }
        
        print("✅ Debug: Sufficient storage available - \(getFormattedAvailableCapacity())")
    }
    
    private func estimateRomSize() -> Int64 {
        // ROM size estimation based on platform/name patterns
        let romName = rom.name.lowercased()
        
        // Large ROM patterns (CD-based systems)
        if romName.contains("cd") || romName.contains("iso") || romName.contains("chd") {
            return 700 * 1024 * 1024  // 700MB estimate for CD ROMs
        }
        
        // DVD-based systems
        if romName.contains("dvd") || romName.contains("wii") || romName.contains("ps2") {
            return 4 * 1024 * 1024 * 1024  // 4GB estimate for DVD ROMs
        }
        
        // Cartridge-based systems
        return 32 * 1024 * 1024  // 32MB estimate for cartridge ROMs
    }
    
    
    var canUpload: Bool {
        if isLocalDeviceSelected {
            // For local device, no need for targetPath
            return !isUploading && !selectedFiles.isEmpty
        } else {
            // For SFTP devices, need connection and targetPath
            return selectedConnection != nil && targetPath != nil && !isUploading && !selectedFiles.isEmpty
        }
    }
    
    var storageWarning: String? {
        guard let availableBytes = getAvailableStorageCapacity() else {
            return nil
        }
        
        let requiredBytes: Int64
        if !selectedFilesList.isEmpty {
            requiredBytes = selectedFilesList.reduce(0) { $0 + $1.fileSizeBytes }
        } else {
            requiredBytes = estimateRomSize()
        }
        
        let requiredBytesWithBuffer = Int64(Double(requiredBytes) * 1.2)
        
        if availableBytes < requiredBytesWithBuffer {
            let availableStr = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
            let requiredStr = ByteCountFormatter.string(fromByteCount: requiredBytesWithBuffer, countStyle: .file)
            return "⚠️ Low storage: \(availableStr) available, \(requiredStr) needed"
        }
        
        return nil
    }
    
    var uploadProgressText: String {
        if totalFiles > 1 {
            // Multi-file upload progress
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let uploadedText = formatter.string(fromByteCount: uploadedBytes)
            let totalText = formatter.string(fromByteCount: totalBytes)
            return "File \(currentFileIndex + 1)/\(totalFiles) - \(uploadedText) / \(totalText)"
        } else if totalBytes > 0 {
            // Single file upload progress
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let uploadedText = formatter.string(fromByteCount: uploadedBytes)
            let totalText = formatter.string(fromByteCount: totalBytes)
            return "\(uploadedText) / \(totalText)"
        }
        return "Preparing..."
    }
    
    // MARK: - File Validation
    
    private func validateDownloadedFile(at localPath: String, fileInfo: RomFileInfo) async throws {
        print("🔍 Validating downloaded file: \(fileInfo.fileName)")
        prepareMessage = "Validating \(fileInfo.fileName)..."
        
        // Use file info from API response for validation
        let expectedSize = fileInfo.fileSizeBytes
        print("🔍 Expected size from fileInfo: \(expectedSize)")
        
        // Validate the file
        let result = validateDownloadedFile(
            at: localPath,
            expectedSize: expectedSize,
            expectedChecksum: nil // We don't have checksum in RomFileInfo
        )
        
        print("🔍 Validation result: valid=\(result.isValid), actualSize=\(result.actualSize)")
        
        if !result.isValid {
            print("❌ File validation failed: \(result.errorMessage ?? "Unknown error")")
            throw SFTPError.fileValidationFailed(result.errorMessage ?? "File integrity check failed")
        }
        
        print("✅ File validation successful: \(fileInfo.fileName)")
    }
    
    // MARK: - File System Utilities (temporary - should be moved to FileSystemUseCases)
    
    private func getTemporaryFilePath(for fileName: String) -> String {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent(fileName).path
    }
    
    private func cleanupTemporaryFile(at path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
    
    private func getFileSize(at path: String) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func checkAvailableStorage(requiredBytes: Int64) -> Bool {
        guard let availableBytes = getAvailableStorageCapacity() else {
            return false
        }
        return availableBytes >= requiredBytes
    }
    
    private func getAvailableStorageCapacity() -> Int64? {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            print("Error checking available storage: \(error)")
            return nil
        }
    }
    
    private func getFormattedAvailableCapacity() -> String {
        guard let bytes = getAvailableStorageCapacity() else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func validateDownloadedFile(at localPath: String, expectedSize: Int64?, expectedChecksum: String?) -> FileValidationResult {
        do {
            let actualSize = try getFileSize(at: localPath)
            
            if let expectedSize = expectedSize, expectedSize > 0 {
                if actualSize != expectedSize {
                    return FileValidationResult(
                        isValid: false,
                        actualSize: actualSize,
                        expectedSize: expectedSize,
                        actualChecksum: "",
                        expectedChecksum: expectedChecksum,
                        errorMessage: "File size mismatch: expected \(expectedSize), got \(actualSize)"
                    )
                }
            }
            
            return FileValidationResult(
                isValid: true,
                actualSize: actualSize,
                expectedSize: expectedSize,
                actualChecksum: "",
                expectedChecksum: expectedChecksum,
                errorMessage: nil
            )
            
        } catch {
            return FileValidationResult(
                isValid: false,
                actualSize: 0,
                expectedSize: nil,
                actualChecksum: "",
                expectedChecksum: nil,
                errorMessage: "Validation failed: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Duplicate Detection
    
    private func checkForDuplicates() async {
        guard let connection = selectedConnection,
              let targetPath = targetPath,
              !selectedFilesList.isEmpty else {
            // Clear duplicates if no connection/path/files selected
            duplicateWarnings.removeAll()
            return
        }
        
        isCheckingDuplicates = true
        duplicateWarnings.removeAll()
        
        do {
            // List files in target directory
            let directoryItems = try await listDirectoryUseCase.execute(at: targetPath, connection: connection)
            
            // Check each selected file for duplicates
            for fileInfo in selectedFilesList {
                let remotePath = targetPath.hasSuffix("/") ? "\(targetPath)\(fileInfo.fileName)" : "\(targetPath)/\(fileInfo.fileName)"
                
                // Find matching file in directory (not directory)
                if let existingFile = directoryItems.first(where: { $0.name == fileInfo.fileName && !$0.isDirectory }),
                   let existingSize = existingFile.size {
                    let duplicateInfo = DuplicateFileInfo(
                        fileName: fileInfo.fileName,
                        existingSize: existingSize,
                        newSize: fileInfo.fileSizeBytes,
                        remotePath: remotePath
                    )
                    duplicateWarnings[fileInfo.fileName] = duplicateInfo
                }
            }
            
        } catch {
            print("⚠️ Could not check for duplicates: \(error)")
            // Don't show error to user - duplicate check is optional
        }
        
        isCheckingDuplicates = false
    }
}
