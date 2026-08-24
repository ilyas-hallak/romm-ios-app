//
//  RomDetailView.swift
//  romm
//
//  Created by Ilyas Hallak on 21.08.25.
//

import SwiftUI
import SafariServices

struct RomDetailView: View {
    let rom: Rom
    @State private var viewModel = RomDetailViewModel()

    @EnvironmentObject private var appData: AppData
    /// Observed so the Play button appears as soon as the in-app emulator is
    /// switched on in Settings, without needing a fresh push of this screen.
    @ObservedObject private var experimentalSettings = ExperimentalFeatureSettings.shared
    @State private var downloadButtonFrame: CGRect = .zero
    /// Mirrors the native tab-bar minimize (which has no readable state): true
    /// once the scroll view has moved down far enough that the bar collapses.
    @State private var tabBarMinimized: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0
    @State private var showTitle: Bool = false
    @State private var selectedTab: DetailTab = .details
    @State private var dominantColor: Color? = nil
    @State private var isHashesExpanded: Bool = false
    @State private var showingSFTPUpload = false
    @State private var showingCollectionPicker = false
    @State private var showingFullScreenPDF = false
    @State private var selectedGameDataTab: GameDataTabType = .states
    /// Shown instead of booting straight away when the ROM has save states, so
    /// the user gets the resume/new-game choice, same as in the Downloads tab.
    @State private var showingPreLaunch = false
    /// Slot picked in the pre-launch sheet; read by the emulator cover builder.
    @State private var pendingResumeSlot: Int?
    /// Distinguishes "user picked a slot" from "user cancelled" once the
    /// pre-launch sheet has dismissed.
    @State private var shouldLaunchAfterPreLaunch = false
    /// Engine resolved before the pre-launch sheet opened, booted once the
    /// sheet is gone so the choice and the launch stay consistent.
    @State private var preLaunchDecision: LaunchDecision?
    private let saveStore: PSaveStore = DefaultDependencyFactory.shared.saveStore

    enum DetailTab: String, CaseIterable {
        case details = "DETAILS"
        case manual = "MANUAL"
        case game = "GAME DATA"
    }
    
    enum GameDataTabType: String, CaseIterable {
        case states = "States"
        case saves = "Saves"
    }
    
    private enum CoordinateSpaces {
        case scrollView
    }
    
    init(rom: Rom) {
        self.rom = rom
    }
    
    // Create ROM object for currently selected variant (original or sibling)
    private var currentSelectedRom: Rom {
        guard let romDetails = viewModel.romDetails else { return rom }
        
        // Use the best available file name (fsName > fileName > name)
        let bestFileName = romDetails.fsName ?? romDetails.fileName ?? romDetails.name
        
        // Create a Rom object from current RomDetails for SFTP upload
        // IMPORTANT: Always use original ROM ID for API compatibility, even for siblings
        return Rom(
            id: rom.id, // Use original ROM ID, not sibling ID
            name: romDetails.name,
            slug: rom.slug, // Keep original slug
            summary: romDetails.summary,
            platformId: romDetails.platformId,
            urlCover: romDetails.urlCover,
            releaseYear: rom.releaseYear, // Keep original release year
            isFavourite: romDetails.isFavourite,
            hasRetroAchievements: romDetails.hasRetroAchievements,
            isPlayable: rom.isPlayable, // Keep original playable status
            sizeBytes: romDetails.sizeBytes,
            createdAt: rom.createdAt, // Keep original created at
            rating: rom.rating, // Keep original rating
            languages: rom.languages, // Keep original languages
            regions: rom.regions, // Keep original regions
            fileName: bestFileName, // Use best available file name
            platformSlug: rom.platformSlug // Keep original platform slug
        )
    }


    var body: some View {
        ScrollView {
                VStack(spacing: 0) {
                    // Hero Image with your ParallaxHeader
                    ParallaxHeader(
                        coordinateSpace: CoordinateSpaces.scrollView,
                        defaultHeight: 400
                    ) {
                        ZStack(alignment: .top) {
                            CachedKFImage(urlString: rom.urlCover) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .onAppear {
                                        extractDominantColor(from: image)
                                    }
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray)
                                    .overlay(
                                        Image(systemName: "gamecontroller")
                                            .font(.system(size: 80))
                                            .foregroundColor(.white)
                                    )
                            }
                            
                            // Semi-transparent overlay in navbar area for better button visibility
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .black.opacity(0.3), location: 0.0),
                                    .init(color: .black.opacity(0.1), location: 0.3),
                                    .init(color: .clear, location: 0.5)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                    
                    // Content section with blur effect
                    VStack(spacing: 0) {
                        titleBlock
                        actionBar
                        stickyTabNavigation
                        tabContentSection
                        Spacer(minLength: 100)
                    }
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 20)
                    .background(
                        Group {
                            if let dominantColor = dominantColor {
                                dominantColor
                                    .opacity(0.08)
                                    .blur(radius: 30)
                                    .background(.ultraThickMaterial)
                            } else {
                                Color(.systemBackground)
                                    .opacity(0.9)
                                    .background(.ultraThickMaterial)
                            }
                        }
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 20
                        )
                    )
                    .onChange(of: selectedTab) { _, newTab in
                        if newTab == .manual && viewModel.manual == nil && !viewModel.isLoadingManual {
                            Task {
                                await viewModel.loadManual(for: rom.id)
                            }
                        } else if newTab == .game && viewModel.saves.isEmpty && viewModel.states.isEmpty && !viewModel.isLoadingSaves && !viewModel.isLoadingStates {
                            Task {
                                async let savesTask = viewModel.loadSaves(for: rom.id)
                                async let statesTask = viewModel.loadStates(for: rom.id)
                                _ = await (savesTask, statesTask)
                            }
                        }
                    }
                    .sheet(item: Binding(
                        get: { viewModel.shareItem },
                        set: { viewModel.shareItem = $0 }
                    ), onDismiss: {
                        viewModel.cleanupShareTemp()
                    }) { item in
                        ShareSheet(activityItems: item.urls) { activityType in
                            guard let activityType else { return }
                            viewModel.handoffDidComplete(
                                romId: currentSelectedRom.id,
                                receivingBundleIdentifier: activityType
                            )
                        }
                    }
                    .sheet(isPresented: $showingSFTPUpload) {
                        SFTPUploadView(rom: currentSelectedRom)
                    }
                    .sheet(isPresented: $showingCollectionPicker) {
                        CollectionPickerView(
                            rom: rom,
                            isPresented: $showingCollectionPicker,
                            onCollectionChanged: {
                                // Reload ROM details when collections change
                                Task {
                                    await viewModel.loadRomDetails(romId: rom.id)
                                }
                            }
                        )
                    }
                    .fullScreenCover(isPresented: $showingFullScreenPDF) {
                        if let pdfData = viewModel.manualPDFData {
                            FullScreenPDFViewer(
                                pdfData: pdfData,
                                title: "\(rom.name) Manual"
                            )
                        }
                    }
                    .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                        Button("OK") {
                            viewModel.clearError()
                        }
                    } message: {
                        Text(viewModel.errorMessage ?? "")
                    }
                    .alert("Download Failed", isPresented: Binding(
                        get: { viewModel.downloadError != nil },
                        set: { if !$0 { viewModel.downloadError = nil } }
                    )) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(viewModel.downloadError ?? "")
                    }
                }
            }
            .overlay(alignment: .top) {
                // Small gradient overlay from top for better NavigationBar visibility
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black.opacity(0.4), location: 0.0),
                        .init(color: .black.opacity(0.2), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .ignoresSafeArea(edges: .top)
            }
            .coordinateSpace(name: CoordinateSpaces.scrollView)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > 40
            } action: { _, minimized in
                tabBarMinimized = minimized
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitle(showTitle ? rom.name : "", displayMode: .inline)
            .navigationBarBackButtonHidden(false)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
                // Show title when content view reaches navbar (around 300px up from original position)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTitle = scrollOffset < -300
                    print(scrollOffset)
                }
            }
            .fullScreenCover(item: $viewModel.launchDecision, onDismiss: {
                viewModel.emulatorPresentationDidEnd()
                pendingResumeSlot = nil
                OrientationLock.set(.portrait, rotateTo: .portrait)
                // A session may have written a new save state or battery save.
                Task { await viewModel.loadRomDetails(romId: rom.id) }
            }) { decision in
                EmulatorRouterView(decision: decision, resumeSlot: pendingResumeSlot)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPreLaunch, onDismiss: {
                // Boot only once the sheet is fully gone. Presenting the emulator's
                // full screen cover while the sheet is still dismissing can swallow
                // the presentation entirely.
                let decision = preLaunchDecision
                preLaunchDecision = nil
                guard shouldLaunchAfterPreLaunch, let decision else {
                    // Sheet was swiped away, release the Play button's spinner.
                    viewModel.emulatorPresentationDidEnd()
                    return
                }
                shouldLaunchAfterPreLaunch = false
                viewModel.present(decision, rom: currentSelectedRom)
            }) {
                PreLaunchSheet(
                    romName: currentSelectedRom.name,
                    romId: rom.id,
                    saveStore: saveStore
                ) { resumeSlot in
                    pendingResumeSlot = resumeSlot
                    shouldLaunchAfterPreLaunch = true
                    showingPreLaunch = false
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                Task {
                    await viewModel.loadRomDetails(romId: rom.id)
                }
                viewModel.refreshDownloadState(romId: rom.id)
                viewModel.refreshPlayTarget()
            }
            .toast(
                isPresented: $viewModel.showAddedToast,
                message: "Added to downloads",
                type: .success,
                duration: 2.0
            )
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(spacing: 12) {
            // Platform (small, secondary)
            if let platform = rom.platform {
                Text(platform.name.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            
            // ROM Name (large, bold)
            Text(rom.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .accessibility(addTraits: .isHeader)
            
            // Publisher/Developer & Platform (small)
            VStack(spacing: 4) {
                if let details = viewModel.romDetails {
                    // Developer/Publisher
                    if let developer = details.developer {
                        Text(developer)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    
                    // Platform name in smaller text
                    Text(details.platformDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if viewModel.isLoading {
                    // Small loading dots while details load
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .scaleEffect(viewModel.isLoading ? 1.0 : 0.5)
                                .animation(
                                    Animation
                                        .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                    value: viewModel.isLoading
                                )
                        }
                    }
                    .frame(height: 20)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: viewModel.romDetails != nil)
        }
        .padding(.vertical, 24)
    }
    
    // Removed metaSection - genres now appear in the metadata grid below
    
    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Toggle Favorite Button
                Button(action: { viewModel.toggleFavorite(originalRom: rom) }) {
                    HStack {
                        Image(systemName: viewModel.actualFavoriteStatus ? "heart.fill" : "heart")
                            .foregroundColor(viewModel.actualFavoriteStatus ? .accentColor : .secondary)
                        Text("Favorite")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemGray6).opacity(0.3))
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .accessibility(hint: Text(viewModel.actualFavoriteStatus ? "Remove from favorites" : "Add to favorites"))
                
                // Add to Collection Button
                Button(action: {
                    showingCollectionPicker = true
                }) {
                    HStack {
                        if viewModel.romCollectionsCount > 0 {
                            Image(systemName: "folder.fill.badge.plus")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Collection")
                                .foregroundColor(.secondary)
                            
                            if viewModel.romCollectionsCount > 0 {
                                Text("In \(viewModel.romCollectionsCount) collection\(viewModel.romCollectionsCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(viewModel.romCollectionsCount > 0 ? Color.green.opacity(0.1) : Color(.systemGray6).opacity(0.3))
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .accessibility(hint: Text(viewModel.romCollectionsCount > 0 ? "Manage ROM collections" : "Add this ROM to a collection"))
            }
            
            // Primary action: queue a download to this device. Once the ROM is on
            // the device a compact Play button joins the same row, so users don't
            // have to detour through the Downloads tab to start a game.
            let downloadState = viewModel.downloadButtonState(forRomId: currentSelectedRom.id)
            HStack(spacing: 12) {
                Button(action: {
                    appData.launchDownloadFlight(
                        coverURL: currentSelectedRom.urlCover,
                        from: downloadButtonFrame,
                        // No public API exposes the tab-bar's minimized state, so
                        // derive it from the live scroll offset (see onScrollGeometryChange).
                        tabBarMinimized: tabBarMinimized
                    )
                    viewModel.downloadROM(rom: currentSelectedRom)
                }) {
                    HStack(spacing: 8) {
                        switch downloadState {
                        case .queued:
                            ProgressView().progressViewStyle(.circular).tint(.white)
                            Text("Queued").font(.headline)
                        case .downloading(let progress):
                            if let progress {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .frame(maxWidth: 140)
                                    .animation(.easeOut(duration: 0.4), value: progress)
                                Text("\(Int((progress * 100).rounded()))%")
                                    .font(.headline)
                                    .contentTransition(.numericText())
                                    .animation(.easeOut(duration: 0.4), value: progress)
                            } else {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                                Text("Downloading…").font(.headline)
                            }
                        case .downloaded:
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                        case .failed:
                            Label("Retry Download", systemImage: "arrow.clockwise.circle.fill")
                                .font(.headline)
                        case .idle:
                            Label("Download", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(downloadState == .downloaded ? Color.green : Color.accentColor)
                    )
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .disabled({
                    switch downloadState {
                    case .idle, .failed: return false
                    case .queued, .downloading, .downloaded: return true
                    }
                }())
                .accessibility(hint: Text(downloadState == .downloaded ? "Already downloaded to this device" : "Download this ROM to this device"))
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newFrame in
                    downloadButtonFrame = newFrame
                }

                // Only offered for a ROM that is already on the device, on a
                // platform we can emulate, and with the in-app emulator switched
                // on, so it never leads to a dead end. Handing the ROM to an
                // external app has none of those limits: the other emulator
                // decides what it supports.
                if downloadState == .downloaded
                    && (viewModel.playsExternally
                        || (viewModel.canPlayEmulator && experimentalSettings.isEmulatorEnabled)) {
                    Button(action: { startPlay() }) {
                        Group {
                            if viewModel.isLaunchingEmulator {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.headline)
                            }
                        }
                        .frame(width: 52)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(viewModel.isLaunchingEmulator)
                    .accessibilityLabel("Play")
                    .accessibility(hint: Text(viewModel.playsExternally
                        ? "Play this ROM in the external emulator set in Settings"
                        : "Play this ROM on this device"))
                    .transition(.scale.combined(with: .opacity))
                    // Anchors the "Open in" popover on iPad to the Play button.
                    .background(
                        OpenInMenuPresenter(
                            item: viewModel.openInItem,
                            onSent: { bundleIdentifier in
                                viewModel.handoffDidComplete(
                                    romId: currentSelectedRom.id,
                                    receivingBundleIdentifier: bundleIdentifier
                                )
                            },
                            onDismiss: { viewModel.openInItem = nil },
                            onNoTargets: { viewModel.handoffFoundNoTargets() }
                        )
                    )
                }
            }
            .animation(.easeOut(duration: 0.25), value: downloadState == .downloaded)

            // Secondary actions: open the downloaded file in another app, or send it to a device.
            HStack(spacing: 12) {
                if viewModel.isDownloaded {
                    Button(action: {
                        viewModel.prepareOpenIn(romId: rom.id)
                    }) {
                        Label("Open In…", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemGray6).opacity(0.3))
                            )
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }
                    .accessibility(hint: Text("Open this ROM in another app such as RetroArch or Delta"))
                }

                Button(action: {
                    showingSFTPUpload = true
                }) {
                    Label("Send to Device", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.systemGray6).opacity(0.3))
                        )
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .accessibility(hint: Text("Send this ROM to another device over SFTP"))
            }
        }
        .padding(.bottom, 24)
    }
    
    /// Routes a Play tap: offer resume when save states exist and the engine can
    /// actually load them, otherwise boot straight into a fresh session.
    private func startPlay() {
        Task {
            // An external emulator owns the whole launch, including its own
            // save states, so the resume dialog below never applies to it.
            if await viewModel.playExternally(rom: currentSelectedRom) { return }
            guard let decision = await viewModel.resolveLaunch(rom: currentSelectedRom) else { return }
            let states = (try? saveStore.listStates(romId: rom.id)) ?? []
            guard decision.supportsSaveStates, !states.isEmpty else {
                pendingResumeSlot = nil
                viewModel.present(decision, rom: currentSelectedRom)
                return
            }
            preLaunchDecision = decision
            showingPreLaunch = true
        }
    }

    @ViewBuilder
    private var stickyTabNavigation: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
    }
    
    @ViewBuilder
    private var tabContentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selectedTab {
            case .details:
                detailsContent
            case .manual:
                manualContent
            case .game:
                gameContent
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 100)
    }
    
    @ViewBuilder
    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ROM/Sibling file picker
            romFilePickerRow
            
            if let sizeBytes = viewModel.romDetails?.sizeBytes {
                DetailRow(label: "Size", value: formatFileSize(sizeBytes))
            }
            
            if let details = viewModel.romDetails {
                // Collapsible Hashes Section
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isHashesExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Text("Hashes")
                                .font(.headline)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isHashesExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top)
                    
                    if isHashesExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            if let sha1 = details.sha1Hash {
                                InfoRow(label: "SHA-1", value: sha1)
                            }
                            if let md5 = details.md5Hash {
                                InfoRow(label: "MD5", value: md5)
                            }
                            if let crc = details.crcHash {
                                InfoRow(label: "CRC", value: crc)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                
                // Game Information Section
                gameInfoSection
            }
                        
            if let summary = rom.summary, !summary.isEmpty {
                summarySection(summary)
            }
        }
    }
    
    @ViewBuilder
    private var manualContent: some View {
        VStack(spacing: 24) {
            if viewModel.isLoadingManual {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Loading manual...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
            } else if viewModel.manualPDFData != nil {
                VStack(spacing: 20) {
                    // Open manual button
                    Button(action: {
                        showingFullScreenPDF = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title3)
                            
                            Text("Open Manual")
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    
                    Spacer()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No manual available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("This ROM doesn't have a manual or it hasn't been uploaded yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 60)
            }
        }
    }
    
    @ViewBuilder
    private var gameContent: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingSaves || viewModel.isLoadingStates {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Loading game data...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
            } else {
                // Game Data Tabs
                HStack(spacing: 0) {
                    ForEach(GameDataTabType.allCases, id: \.self) { tabType in
                        Button(action: {
                            selectedGameDataTab = tabType
                        }) {
                            GameDataTab(
                                title: tabType.rawValue,
                                isSelected: selectedGameDataTab == tabType,
                                icon: tabType == .states ? "gamecontroller.fill" : "folder.fill"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 20)
                
                // Content Area
                VStack(spacing: 0) {
                    switch selectedGameDataTab {
                    case .states:
                        if !viewModel.states.isEmpty {
                            ForEach(viewModel.states) { state in
                                GameDataCard(
                                    fileName: state.fileNameNoExt,
                                    fileSize: formatFileSize(state.fileSizeBytes),
                                    dateUpdated: formatDate(state.updatedAt),
                                    screenshot: state.screenshot
                                )
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "gamecontroller")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                
                                Text("No states available")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 60)
                        }
                    case .saves:
                        if !viewModel.saves.isEmpty {
                            ForEach(viewModel.saves) { save in
                                GameDataCard(
                                    fileName: save.fileNameNoExt,
                                    fileSize: formatFileSize(save.fileSizeBytes),
                                    dateUpdated: formatDate(save.updatedAt),
                                    screenshot: save.screenshot
                                )
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "folder")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                
                                Text("No saves available")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 60)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top, 20)
            }
        }
    }
    
    @ViewBuilder
    private var gameInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)
                .padding(.top, 16)
            
            // Show details immediately - use available data and fill in more as it loads
            let companies = getCompanies(from: viewModel.romDetails)
            let metadataItems = buildMetadataItems(rom: rom, details: viewModel.romDetails, companies: companies)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(metadataItems, id: \.id) { item in
                    item.view
                }
            }
        }
    }
    
    @ViewBuilder
    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Summary")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }
    
    private func extractDominantColor(from image: Image) {
        let renderer = ImageRenderer(content: image)
        renderer.scale = 1.0
        
        if let uiImage = renderer.uiImage,
           let dominantUIColor = uiImage.dominantColor() {
            DispatchQueue.main.async {
                self.dominantColor = Color(dominantUIColor)
            }
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getCompanies(from details: RomDetails?) -> [String] {
        guard let details = details else { return [] }
        
        // Prioritize companies array from metadatum, fallback to developer/publisher
        if !details.companies.isEmpty {
            return details.companies
        }
        
        var companies: [String] = []
        if let developer = details.developer {
            companies.append(developer)
        }
        if let publisher = details.publisher, publisher != details.developer {
            companies.append(publisher)
        }
        return companies
    }
    
    private func buildMetadataItems(rom: Rom, details: RomDetails?, companies: [String]) -> [MetadataItemWrapper] {
        var items: [MetadataItemWrapper] = []
        
        // Add all available metadata in priority order
        if !rom.regions.isEmpty {
            items.append(MetadataItemWrapper(
                id: "regions",
                view: AnyView(CompactMetadataColumn(label: "Regions", items: rom.regions))
            ))
        }
        
        if !rom.languages.isEmpty {
            items.append(MetadataItemWrapper(
                id: "languages", 
                view: AnyView(CompactMetadataColumn(label: "Languages", items: rom.languages))
            ))
        }
        
        if let details = details, !details.genre.isEmpty {
            items.append(MetadataItemWrapper(
                id: "genres",
                view: AnyView(CompactMetadataColumn(label: "Genres", items: details.genre))
            ))
        }
        
        if let details = details, !details.franchises.isEmpty {
            items.append(MetadataItemWrapper(
                id: "franchises",
                view: AnyView(CompactMetadataColumn(label: "Franchises", items: details.franchises))
            ))
        }
        
        if !companies.isEmpty {
            items.append(MetadataItemWrapper(
                id: "companies",
                view: AnyView(CompactMetadataColumn(label: "Companies", items: companies))
            ))
        }
        
        if let details = details, !details.gameModes.isEmpty {
            items.append(MetadataItemWrapper(
                id: "gameModes",
                view: AnyView(CompactMetadataColumn(label: "Game Modes", items: details.gameModes))
            ))
        }
        
        if let details = details, !details.ageRatings.isEmpty {
            items.append(MetadataItemWrapper(
                id: "ageRatings",
                view: AnyView(CompactMetadataColumn(label: "Age Ratings", items: details.ageRatings))
            ))
        }
        
        if let details = details, let rating = details.averageRating {
            items.append(MetadataItemWrapper(
                id: "rating",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rating")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            
                            Text(String(format: "%.1f", rating))
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Text("/ 100")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
            ))
        }
        
        return items
    }
    
    @ViewBuilder
    private var romFilePickerRow: some View {
        HStack(spacing: 0) {
            // Label
            Text("File")
                .font(.system(.subheadline, weight: .semibold))                
            
            Spacer()
            
            // Picker or simple text
            if viewModel.availableRomOptions.count > 1 {
                // Show picker if siblings exist
                Menu {
                    ForEach(viewModel.availableRomOptions, id: \.id) { option in
                        Button(action: {
                            Task {
                                if option.id == viewModel.originalRomDetails?.id {
                                    // Selected original ROM
                                    await viewModel.switchToSibling(nil)
                                } else {
                                    // Selected a sibling
                                    await viewModel.switchToSibling(option.id)
                                }
                            }
                        }) {
                            HStack {
                                Text(option.name)
                                    .font(fontSizeForText(option.name))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                // Show checkmark for currently selected option
                                if option.id == viewModel.romDetails?.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.currentRomName)
                            .font(fontSizeForText(viewModel.currentRomName))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(viewModel.isLoading)
            } else {
                // Show simple text if no siblings
                Text(viewModel.currentRomName)
                    .font(fontSizeForText(viewModel.currentRomName))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private func fontSizeForText(_ text: String) -> Font {
        // Responsive font sizing based on text length
        if text.count > 50 {
            return .caption
        } else if text.count > 30 {
            return .caption2
        } else {
            return .subheadline
        }
    }
}

#Preview {
    NavigationStack {
        RomDetailView(rom: Rom(
            id: 1,
            name: "Super Mario Bros.",
            platformId: 1,
            urlCover: nil,
            isFavourite: false,
            hasRetroAchievements: true,
            isPlayable: true
        ))
    }
}

// MARK: - Supporting Components

struct GenreCapsule: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundColor(.primary)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            Spacer()
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}

struct MetadataItemWrapper: Identifiable {
    let id: String
    let view: AnyView
}

struct CompactMetadataColumn: View {
    let label: String
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.prefix(3), id: \.self) { item in
                    Text(item)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                if items.count > 3 {
                    Text("+\(items.count - 3) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetadataRow: View {
    let label: String
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.4),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .animation(
                    Animation
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: phase
                )
            )
            .onAppear {
                withAnimation {
                    phase = 200
                }
            }
            .mask(content)
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

extension UIImage {
    func dominantColor() -> UIColor? {
        guard let cgImage = self.cgImage else { return nil }
        
        let width = 50
        let height = 50
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var colorCount: [UIColor: Int] = [:]
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                let r = CGFloat(pixelData[pixelIndex]) / 255.0
                let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0
                
                let color = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                colorCount[color, default: 0] += 1
            }
        }
        
        return colorCount.max(by: { $0.value < $1.value })?.key
    }
}

struct ParallaxHeader<Content: View, Space: Hashable>: View {
    let content: () -> Content
    let coordinateSpace: Space
    let defaultHeight: CGFloat
    
    init(
        coordinateSpace: Space,
        defaultHeight: CGFloat,
        @ViewBuilder _ content: @escaping () -> Content
    ) {
        self.content = content
        self.coordinateSpace = coordinateSpace
        self.defaultHeight = defaultHeight
    }
    
    var body: some View {
        GeometryReader { proxy in
            let offset = offset(for: proxy)
            let heightModifier = heightModifier(for: proxy)
            content()
                .edgesIgnoringSafeArea(.horizontal)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height + heightModifier
                )
                .offset(y: offset)
                .onAppear {
                    // Extract dominant color from cover image
                    // This is handled in the main view where AsyncImage is defined
                }
        }.frame(height: defaultHeight)
    }
    
    
    private func offset(for proxy: GeometryProxy) -> CGFloat {
        let frame = proxy.frame(in: .named(coordinateSpace))
        if frame.minY < 0 {
            return -frame.minY * 0.8
        }
        return -frame.minY
    }
    
    private func heightModifier(for proxy: GeometryProxy) -> CGFloat {
        let frame = proxy.frame(in: .named(coordinateSpace))
        return max(0, frame.minY)
    }
}

struct ParallaxExample: View {
    private enum CoordinateSpaces {
        case scrollView
    }
    var body: some View {
        ScrollView {
            ParallaxHeader(
                coordinateSpace: CoordinateSpaces.scrollView,
                defaultHeight: 400
            ) {
                Image("flower")
                    .resizable()
                    .scaledToFill()
            }
            Rectangle()
                .fill(.blue)
                .frame(height: 1000)
                .shadow(color: .black.opacity(0.8), radius: 10, y: -10)
                .offset(y: -10)
        }
        .coordinateSpace(name: CoordinateSpaces.scrollView)
        .edgesIgnoringSafeArea(.top)
        
    }
}

// MARK: - Game Data Components

struct GameDataTab: View {
    let title: String
    let isSelected: Bool
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            
            Rectangle()
                .fill(isSelected ? Color.secondary.opacity(0.3) : Color.clear)
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isSelected ? Color.secondary.opacity(0.1) : Color.clear)
    }
}

struct GameDataCard: View {
    let fileName: String
    let fileSize: String
    let dateUpdated: String
    let screenshot: ScreenshotSchema?
    
    var body: some View {
        VStack(spacing: 0) {
            // Screenshot/Preview Area
            ZStack {
                if let screenshot = screenshot {
                    CachedKFImage(urlString: screenshot.downloadPath) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipped()
                            .cornerRadius(8)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.8),
                                    Color.purple.opacity(0.4),
                                    Color.orange.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(height: 200)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            )
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "gamecontroller")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // File Info Area
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(fileName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Image(systemName: "cloud.download")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Text(fileSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Updated: \(dateUpdated)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
