import SwiftUI

struct LocalDeviceDetailView: View {
    @State private var viewModel = LocalDeviceDetailViewModel()
    @State private var showingDeviceManagement = false
    @State private var showingDownloadQueue = false

    private let downloadQueue = DownloadQueueManager.shared

    private var device: LocalDevice {
        LocalDeviceManager.shared.currentDevice
    }

    var body: some View {
        Group {
            if viewModel.hasDownloadedROMs {
                downloadedROMsList
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingDownloadQueue = true
                } label: {
                    downloadQueueIcon
                }
                .accessibilityLabel("Download Queue")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingDeviceManagement = true
                } label: {
                    Image(systemName: "server.rack")
                }
                .accessibilityLabel("Manage Devices")
            }
        }
        .sheet(isPresented: $showingDownloadQueue) {
            DownloadQueueView()
        }
        .onChange(of: downloadQueue.finishedCount) { _, _ in
            Task { await viewModel.loadDownloadedROMsAsync() }
        }
        .sheet(isPresented: $showingDeviceManagement) {
            NavigationStack {
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
        .task {
            // Load data on first appear
            await viewModel.loadDownloadedROMsAsync()
            await viewModel.loadPlatformDisplayNames()
        }
        .refreshable {
            await viewModel.loadDownloadedROMsAsync()
            await viewModel.refreshStorageInfo()
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private var downloadQueueIcon: some View {
        let count = downloadQueue.activeCount
        return Image(systemName: "arrow.down.circle")
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(Color.red))
                        .offset(x: 8, y: -8)
                }
            }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Downloaded ROMs")
                .font(.title2)
                .fontWeight(.semibold)

            Text("ROMs downloaded to this device will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            storageInfoCard
                .padding(.top, 20)
        }
        .padding()
    }

    private var downloadedROMsList: some View {
        List {
            Section {
                storageInfoCard
            }

            Section("Platforms") {
                ForEach(viewModel.platformNames, id: \.self) { platformName in
                    if let roms = viewModel.romsByPlatform[platformName] {
                        NavigationLink {
                            PlatformROMsListView(
                                platformName: platformName,
                                viewModel: viewModel,
                                onDelete: { rom in
                                    viewModel.deleteROM(rom)
                                }
                            )
                        } label: {
                            HStack(spacing: 12) {
                                if let slug = roms.first?.platformSlug {
                                    Image(PlatformIcon.assetName(for: slug))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.displayName(forPlatformName: platformName))
                                        .font(.headline)
                                        .lineLimit(2)

                                    Text("\(roms.count) ROM\(roms.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                // Total size for this platform
                                let totalSize = roms.reduce(0) { $0 + $1.totalSizeBytes }
                                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var storageInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(romSummary)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(device.availableStorageFormatted) free")
                    .font(.subheadline)
                    .foregroundColor(device.hasLowStorage ? .orange : .secondary)
            }

            StorageBar(
                romBytes: viewModel.totalDownloadedSize,
                availableBytes: device.availableStorageBytes,
                totalBytes: device.totalStorageBytes
            )

            HStack(spacing: 10) {
                legendItem("ROMs", color: SetupTheme.blobPurple)
                legendItem("Apps & System", color: StorageBar.otherColor)
                legendItem("Free", color: StorageBar.freeColor)
                Spacer(minLength: 4)
                Text("of \(device.totalStorageFormatted)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
    }

    private var romSummary: String {
        let count = viewModel.downloadedROMs.count
        guard count > 0 else { return "No ROMs yet" }
        return "\(viewModel.totalDownloadedSizeFormatted) in \(count) ROM\(count == 1 ? "" : "s")"
    }
}

/// Device storage split into ROMs, everything else, and free space.
private struct StorageBar: View {
    let romBytes: Int64
    let availableBytes: Int64
    let totalBytes: Int64

    static let otherColor = Color.gray.opacity(0.5)
    static let freeColor = Color.gray.opacity(0.2)

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(SetupTheme.blobPurple)
                    .frame(width: romWidth(in: geometry.size.width))
                Rectangle()
                    .fill(Self.otherColor)
                    .frame(width: geometry.size.width * fraction(of: otherBytes))
                Spacer(minLength: 0)
            }
            .background(Self.freeColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
    }

    private var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    // ROMs are part of the used space, so they are clamped to it.
    private var otherBytes: Int64 {
        usedBytes - min(romBytes, usedBytes)
    }

    // Keeps a small library visible on a large disk.
    private func romWidth(in totalWidth: CGFloat) -> CGFloat {
        guard romBytes > 0 else { return 0 }
        return max(4, totalWidth * fraction(of: romBytes))
    }

    private func fraction(of bytes: Int64) -> CGFloat {
        guard totalBytes > 0 else { return 0 }
        return CGFloat(min(bytes, usedBytes)) / CGFloat(totalBytes)
    }
}

#Preview {
    NavigationStack {
        LocalDeviceDetailView()
    }
}
