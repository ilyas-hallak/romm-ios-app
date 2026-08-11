import SwiftUI

struct LocalDeviceDetailView: View {
    @State private var viewModel = LocalDeviceDetailViewModel()
    @State private var showingDeviceManagement = false
    @State private var showingDownloadQueue = false
    @State private var isStorageExpanded = false

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
                                    Image(slug)
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
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isStorageExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Storage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(device.storageUsagePercentage))%")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(device.hasLowStorage ? .orange : .primary)
                            Spacer()
                            Text("\(viewModel.totalDownloadedSizeFormatted) of \(device.totalStorageFormatted)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(device.hasLowStorage ? Color.orange : Color.blue)
                                    .frame(
                                        width: max(0, geometry.size.width * CGFloat(device.storageUsagePercentage / 100)),
                                        height: 6
                                    )
                            }
                        }
                        .frame(height: 6)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isStorageExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isStorageExpanded {
                Divider()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(device.availableStorageFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(device.hasLowStorage ? .orange : .primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.totalDownloadedSizeFormatted) · \(viewModel.downloadedROMs.count) ROMs")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    NavigationStack {
        LocalDeviceDetailView()
    }
}
