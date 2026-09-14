//
//  RomListWithSectionIndex.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI
import os

// MARK: - Universal ROM List with Native Section Index Titles
struct RomListWithSectionIndex: View {
    private let logger = Logger.ui
    let roms: [Rom]
    let viewMode: ViewMode
    let onRefresh: (() async -> Void)?
    let onLoadMore: (() async -> Void)?
    let charIndex: [String: Int] // API-provided char index
    let selectedChar: String? // Currently selected character
    let onCharTapped: ((String?) async -> Void)? // Callback for char filtering
    let onSort: ((String, String) async -> Void)? // Callback for sorting
    let currentOrderBy: String // Current sort field from ViewModel
    let currentOrderDir: String // Current sort direction from ViewModel
    let canLoadMore: Bool
    let platform: Platform? // Platform information for displaying icons
    
    @State private var loadMoreTriggeredRoms: Set<Int> = []
    @State private var lastRomCount: Int = 0
    @State private var prefetchWindow = CoverPrefetchWindow()

    /// Start loading the next page while this many ROMs are still ahead, so the list does not
    /// visibly stall once the user reaches the bottom.
    private static let loadMoreThreshold = 12

    var body: some View {
        Group {
            if viewMode == .table {
                ZStack(alignment: .trailing) {
                    RomTableView(
                        roms: roms, 
                        onRefresh: onRefresh, 
                        onLoadMore: onLoadMore,
                        onSort: onSort,
                        canLoadMore: canLoadMore,
                        currentOrderBy: currentOrderBy,
                        currentOrderDir: currentOrderDir,
                        loadMoreTriggeredRoms: $loadMoreTriggeredRoms
                    )
                    
                    // Custom Character Filter Picker for Table View
                    VStack {
                        Spacer()
                        CharFilterPicker(
                            charIndex: charIndex,
                            selectedChar: selectedChar,
                            onCharSelected: { char in
                                Task {
                                    await onCharTapped?(char)
                                }
                            }
                        )
                        Spacer()
                    }
                }
            } else {
                ZStack(alignment: .trailing) {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedSections, id: \.letter) { section in
                            Section {
                                if viewMode == .bigCard {
                                    // Grid layout for big cards - 2 columns
                                    LazyVGrid(columns: [
                                        GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)
                                    ], spacing: 16) {
                                        ForEach(section.roms) { rom in
                                            NavigationLink {
                                                RomDetailView(rom: rom)
                                            } label: {
                                                BigRomCardView(rom: rom, platform: platform)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 16)
                                                            .fill(Color(.secondarySystemGroupedBackground))
                                                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 16)
                                                            .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                                                    )                                                    
                                            }
                                            .buttonStyle(CardButtonStyle())
                                            .onAppear {
                                                prefetchWindow.itemAppeared(id: rom.id)
                                                triggerLoadMoreIfNeeded(for: rom)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                } else {
                                    // List layout for small cards
                                    ForEach(section.roms) { rom in
                                        NavigationLink {
                                            RomDetailView(rom: rom)
                                        } label: {
                                            romRowView(rom: rom)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .padding(.horizontal, 16)
                                        .onAppear {
                                            prefetchWindow.itemAppeared(id: rom.id)
                                            triggerLoadMoreIfNeeded(for: rom)
                                        }
                                    }
                                }
                            } header: {
                                sectionHeader(section.letter)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)
                                    .background(Color(.systemGroupedBackground))
                            }
                        }
                        .id(selectedChar) // Force refresh when selectedChar changes
                        }
                        .background(Color(.systemGroupedBackground))
                    }
                    .background(Color(.systemGroupedBackground))
                    .refreshable {
                        loadMoreTriggeredRoms.removeAll()
                        await onRefresh?()
                    }
                    
                    // Custom Character Filter Picker
                    VStack {
                        Spacer()
                        CharFilterPicker(
                            charIndex: charIndex,
                            selectedChar: selectedChar,
                            onCharSelected: { char in
                                Task {
                                    await onCharTapped?(char)
                                }
                            }
                        )
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            // Reset triggered roms when the rom count changes (new data loaded)
            if lastRomCount != roms.count {
                loadMoreTriggeredRoms.removeAll()
                lastRomCount = roms.count
            }
            refreshPrefetchWindow()
        }
        .onChange(of: roms.count) { oldValue, newValue in
            // Clear triggered roms when new data is loaded
            if newValue != oldValue {
                loadMoreTriggeredRoms.removeAll()
                lastRomCount = newValue
            }
        }
        .onChange(of: roms.coverPrefetchToken) { _, _ in
            refreshPrefetchWindow()
        }
    }
    
    // MARK: - ViewBuilder Functions
    
    @ViewBuilder
    private func sectionHeader(_ letter: String) -> some View {
        Text(letter)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
    }
    
    @ViewBuilder
    private func romRowView(rom: Rom) -> some View {
        switch viewMode {
        case .smallCard:
            SmallRomListRowView(rom: rom)
        case .bigCard:
            BigRomListRowView(rom: rom)
        case .table:
            TableRomRowView(rom: rom)
        }
    }
    
    // MARK: - Computed Properties
    
    private var groupedSections: [RomSection] {
        let grouped = Dictionary(grouping: roms) { rom in
            let firstChar = String(rom.name.prefix(1)).uppercased()
            if firstChar.rangeOfCharacter(from: CharacterSet.letters) != nil {
                return firstChar
            } else {
                return "#"
            }
        }
        
        return grouped.map { key, value in
            RomSection(letter: key, roms: value.sorted { $0.name < $1.name })
        }.sorted { $0.letter < $1.letter }
    }
    
    private var sectionTitles: [String] {
        // Use API charIndex if available, otherwise fallback to grouped sections
        if !charIndex.isEmpty {
            var titles = charIndex.keys.sorted()
            // Add "All" option at the beginning to clear filter
            titles.insert("ALL", at: 0)
            return titles
        } else {
            return groupedSections.map { $0.letter }
        }
    }
    
    // MARK: - Helper Functions
    
    private func scrollToSection(_ title: String) {
        logger.info("Section tapped: \(title)")
        Task {
            // "ALL" means clear filter (pass nil)
            let char = title == "ALL" ? nil : title
            await onCharTapped?(char)
        }
    }
    
    /// IDs of the trailing ROMs that start the next page. Kept as a set so an appearing cell
    /// does not have to search the whole list.
    private var loadMoreTriggerRomIDs: Set<Int> {
        Set(roms.suffix(Self.loadMoreThreshold).map { $0.id })
    }

    private func triggerLoadMoreIfNeeded(for rom: Rom) {
        guard canLoadMore,
              loadMoreTriggerRomIDs.contains(rom.id),
              !loadMoreTriggeredRoms.contains(rom.id) else { return }

        loadMoreTriggeredRoms.insert(rom.id)
        Task {
            await onLoadMore?()
        }
    }

    /// The sections are what the user actually scrolls through, so the prefetch window has to
    /// follow their order and not the order the ROMs arrived in.
    private func refreshPrefetchWindow() {
        prefetchWindow.update(with: groupedSections.flatMap { $0.roms }) { $0.urlCover }
    }
}

// MARK: - Button Styles

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Data Models
struct RomSection {
    let letter: String
    let roms: [Rom]
}

// MARK: - List Row Views optimized for List

struct SmallRomListRowView: View {
    let rom: Rom
    
    var body: some View {
        HStack(spacing: 12) {
            CachedKFImage(urlString: rom.urlCover) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundColor(.gray)
                            .font(.caption)
                    )
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rom.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let year = rom.releaseYear?.description {
                    Text(year)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            RomStatusIcons(rom: rom)
        }
        .padding(.vertical, 2)
    }
}

struct BigRomListRowView: View {
    let rom: Rom
    
    var body: some View {
        HStack(spacing: 12) {
            CachedKFImage(urlString: rom.urlCover) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundColor(.gray)
                            .font(.title2)
                    )
            }
            .frame(width: 60, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rom.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                
                if let year = rom.releaseYear?.description {
                    Text(year)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let summary = rom.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                RomStatusIcons(rom: rom)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Section Index View
struct SectionIndexView: View {
    let titles: [String]
    let onTitleTapped: (String) -> Void
    @State private var activeTitle: String?
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(titles, id: \.self) { title in
                Button(action: {
                    onTitleTapped(title)
                    activeTitle = title
                    
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(activeTitle == title ? .blue : .secondary)
                        .frame(width: 16, height: 14)
                        .background(
                            activeTitle == title ? 
                            Color.blue.opacity(0.2) : Color.clear
                        )
                        .clipShape(Circle())
                }
                .scaleEffect(activeTitle == title ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: activeTitle)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .opacity(0.8)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                activeTitle = nil
            }
        }
    }
}

// MARK: - Sorting Support
enum SortField: String, CaseIterable {
    case name = "name"
    case size = "size" 
    case added = "created_at"
    case released = "release_year"
    case rating = "average_rating"
    
    var displayName: String {
        switch self {
        case .name: return "Title"
        case .size: return "Size"
        case .added: return "Added"
        case .released: return "Released"
        case .rating: return "Rating"
        }
    }
}

enum SortDirection: String {
    case asc = "asc"
    case desc = "desc"
}

// MARK: - ROM Table View with Native SwiftUI Table
struct RomTableView: View {
    let roms: [Rom]
    let onRefresh: (() async -> Void)?
    let onLoadMore: (() async -> Void)?
    let onSort: ((String, String) async -> Void)? // New callback for sorting
    let canLoadMore: Bool
    let currentOrderBy: String // Current sort field from ViewModel
    let currentOrderDir: String // Current sort direction from ViewModel
    @Binding var loadMoreTriggeredRoms: Set<Int>
    @State private var selectedRom: Rom.ID?
    @State private var prefetchWindow = CoverPrefetchWindow()
    @Environment(\.horizontalSizeClass) var sizeClass

    /// Start loading the next page while this many ROMs are still ahead, so the table does not
    /// visibly stall once the user reaches the bottom.
    private static let loadMoreThreshold = 12

    private var isCompact: Bool {
        sizeClass == .compact
    }

    // No local sorting - data comes pre-sorted from server
    private var sortedRoms: [Rom] {
        roms
    }

    var body: some View {
        Group {
            if isCompact {
                // iPhone: Custom scrollable table implementation
                iPhoneTableView
            } else {
                // iPad/Mac: Native Table
                iPadTableView
            }
        }
        .onAppear {
            refreshPrefetchWindow()
        }
        .onChange(of: sortedRoms.coverPrefetchToken) { _, _ in
            refreshPrefetchWindow()
        }
    }
    
    @ViewBuilder
    private var iPadTableView: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                // Custom Header Row with Sortable Columns for iPad
                HStack(spacing: 0) {
                    sortableHeaderButton("Title", field: .name, width: 320, alignment: .leading)
                    sortableHeaderButton("Size", field: .size, width: 80, alignment: .center)
                    sortableHeaderButton("Added", field: .added, width: 100, alignment: .center)
                    sortableHeaderButton("Released", field: .released, width: 80, alignment: .center)
                    sortableHeaderButton("Rating", field: .rating, width: 70, alignment: .center)
                    staticHeaderLabel("Languages", width: 120)
                    staticHeaderLabel("Regions", width: 120)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                
                // Data Rows - Replace Table with custom implementation
                LazyVStack(spacing: 0) {
                    ForEach(sortedRoms) { rom in
                        NavigationLink(destination: RomDetailView(rom: rom)) {
                            HStack(spacing: 0) {
                                // Title Column
                                HStack(spacing: 8) {
                                    CachedKFImage(urlString: rom.urlCover) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.2))
                                            .overlay(
                                                Image(systemName: "gamecontroller")
                                                    .foregroundColor(.gray)
                                                    .font(.caption2)
                                            )
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(rom.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        
                                        RomStatusIcons(rom: rom)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 4)
                                .frame(width: 320, alignment: .leading)
                                
                                // Size Column
                                Group {
                                    if let sizeBytes = rom.sizeBytes {
                                        Text(formatFileSize(sizeBytes))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.accent)
                                    }
                                }
                                .frame(width: 80, alignment: .center)
                                
                                // Added Column
                                Group {
                                    if let createdAt = rom.createdAt {
                                        Text(formatDate(createdAt))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.accent)
                                    }
                                }
                                .frame(width: 100, alignment: .center)
                                
                                // Released Column
                                Group {
                                    if let year = rom.releaseYear?.description {
                                        Text(year)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("-")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .frame(width: 80, alignment: .center)
                                
                                // Rating Column
                                Group {
                                    if let rating = rom.rating {
                                        Text(String(format: "%.1f", rating))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .frame(width: 70, alignment: .center)
                                
                                // Languages Column
                                Group {
                                    if !rom.languages.isEmpty {
                                        HStack(spacing: 4) {
                                            ForEach(rom.languages.prefix(2), id: \.self) { language in
                                                Text(languageEmoji(for: language))
                                                    .font(.caption)
                                            }
                                        }
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.accent)
                                    }
                                }
                                .frame(width: 120, alignment: .center)
                                
                                // Regions Column
                                Group {
                                    if !rom.regions.isEmpty {
                                        HStack(spacing: 4) {
                                            ForEach(rom.regions.prefix(2), id: \.self) { region in
                                                Text(flagEmoji(for: region))
                                                    .font(.caption)
                                            }
                                        }
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.accent)
                                    }
                                }
                                .frame(width: 120, alignment: .center)
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(Color(.systemBackground))
                        .overlay(Rectangle().fill(Color(.separator)).frame(height: 0.5), alignment: .bottom)
                        .onAppear {
                            prefetchWindow.itemAppeared(id: rom.id)
                            triggerLoadMoreIfNeeded(for: rom)
                        }
                    }
                }
            }
            .frame(minWidth: 890)
            
            // Load More Button for Table View
            if canLoadMore {
                Button(action: {
                    Task {
                        await onLoadMore?()
                    }
                }) {
                    HStack {
                        LoadingView()
                            .frame(width: 20, height: 20)
                        Text("Load More ROMs")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.vertical)
            }
        }
        .refreshable {
            loadMoreTriggeredRoms.removeAll()
            await onRefresh?()
        }
    }
    
    @ViewBuilder
    private var iPhoneTableView: some View {
        ScrollView {
            ScrollView(.horizontal, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    // Header Row with Sortable Columns
                    HStack(spacing: 0) {
                        sortableHeaderButton("Title", field: .name, width: 180, alignment: .leading)
                        sortableHeaderButton("Rating", field: .rating, width: 60, alignment: .center)
                        sortableHeaderButton("Size", field: .size, width: 70, alignment: .center)
                        sortableHeaderButton("Added", field: .added, width: 80, alignment: .center)
                        sortableHeaderButton("Released", field: .released, width: 70, alignment: .center)
                        staticHeaderLabel("Languages", width: 80)
                        staticHeaderLabel("Regions", width: 80)
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    
                    // Data Rows
                    ForEach(sortedRoms) { rom in
                        NavigationLink(destination: RomDetailView(rom: rom)) {
                            HStack(spacing: 0) {
                                // Title Column
                                HStack(spacing: 4) {
                                    // Icon
                                    CachedKFImage(urlString: rom.urlCover) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Image(systemName: "gamecontroller")
                                                    .foregroundColor(.gray)
                                                    .font(.caption2)
                                            )
                                    }
                                    .frame(width: 20, height: 20)
                                    
                                    Text(rom.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    Spacer()
                                }
                                .frame(width: 180, alignment: .leading)
                                
                                // Rating Column
                                Text(rom.rating != nil ? String(format: "%.1f", rom.rating!) : "—")
                                    .font(.caption)
                                    .frame(width: 60, alignment: .center)
                                    .foregroundColor(.secondary)
                                
                                // Size Column
                                Text(rom.sizeBytes != nil ? formatFileSize(rom.sizeBytes!) : "—")
                                    .font(.caption)
                                    .frame(width: 70, alignment: .center)
                                    .foregroundColor(.secondary)
                                
                                // Added Column
                                Group {
                                    if let createdAt = rom.createdAt {
                                        Text(formatDate(createdAt))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 80, alignment: .center)
                                
                                // Released Column
                                Text(rom.releaseYear != nil ? "\(rom.releaseYear!)" : "—")
                                    .font(.caption)
                                    .frame(width: 70, alignment: .center)
                                    .foregroundColor(.secondary)
                                
                                // Languages Column
                                Group {
                                    if !rom.languages.isEmpty {
                                        HStack(spacing: 2) {
                                            ForEach(rom.languages.prefix(2), id: \.self) { language in
                                                Text(languageEmoji(for: language))
                                                    .font(.caption)
                                            }
                                        }
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 80, alignment: .center)
                                
                                // Regions Column
                                Group {
                                    if !rom.regions.isEmpty {
                                        HStack(spacing: 2) {
                                            ForEach(rom.regions.prefix(2), id: \.self) { region in
                                                Text(flagEmoji(for: region))
                                                    .font(.caption)
                                            }
                                        }
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 80, alignment: .center)
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .padding(.leading, 8)
                        .background(Color(.systemBackground))
                        .overlay(Rectangle().fill(Color(.separator)).frame(height: 0.5), alignment: .bottom)
                        .onAppear {
                            prefetchWindow.itemAppeared(id: rom.id)
                        }
                    }
                }
                
                // Load More Button for iPhone Table View
                if canLoadMore {
                    Button(action: {
                        Task {
                            await onLoadMore?()
                        }
                    }) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Load More ROMs")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.vertical)
                }
            }
        }
        .refreshable {
            loadMoreTriggeredRoms.removeAll()
            await onRefresh?()
        }
    }
    
    // MARK: - Helper Functions
    
    private var currentSortField: SortField {
        SortField.allCases.first { $0.rawValue == currentOrderBy } ?? .name
    }
    
    private var currentSortDirection: SortDirection {
        SortDirection(rawValue: currentOrderDir) ?? .asc
    }
    
    private func toggleSort(_ field: SortField) {
        let newDirection: SortDirection
        if currentSortField == field {
            newDirection = currentSortDirection == .asc ? .desc : .asc
        } else {
            newDirection = .asc
        }
        
        // Trigger server-side sorting
        Task {
            await onSort?(field.rawValue, newDirection.rawValue)
        }
    }
    
    @ViewBuilder
    private func sortableHeaderButton(_ title: String, field: SortField, width: CGFloat, alignment: Alignment) -> some View {
        Button(action: {
            toggleSort(field)
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(currentSortField == field ? .primary : .secondary)
                    
                    if currentSortField == field {
                        Image(systemName: currentSortDirection == .asc ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    } else {
                        // Show faint sort indicator when not active
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
                .frame(width: width, alignment: alignment)
                
                // Segmented control style underline
                Rectangle()
                    .fill(currentSortField == field ? Color.accentColor : Color.clear)
                    .frame(height: 2)
                    .frame(width: width) // Full width underline
                    .animation(.easeInOut(duration: 0.3), value: currentSortField)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle()) // Make entire area tappable
        // Clean look without background colors
    }
    
    private func staticHeaderLabel(_ title: String, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: width, alignment: .center)
            
            // Empty underline space to match sortable headers
            Rectangle()
                .fill(Color.clear)
                .frame(height: 2)
                .frame(width: width)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }
    
    /// IDs of the trailing ROMs that start the next page. Kept as a set so an appearing row
    /// does not have to search the whole list.
    private var loadMoreTriggerRomIDs: Set<Int> {
        Set(sortedRoms.suffix(Self.loadMoreThreshold).map { $0.id })
    }

    private func triggerLoadMoreIfNeeded(for rom: Rom) {
        guard canLoadMore,
              loadMoreTriggerRomIDs.contains(rom.id),
              !loadMoreTriggeredRoms.contains(rom.id) else { return }

        loadMoreTriggeredRoms.insert(rom.id)
        Task {
            await onLoadMore?()
        }
    }

    private func refreshPrefetchWindow() {
        prefetchWindow.update(with: sortedRoms) { $0.urlCover }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString.prefix(10).description // Fallback: show first 10 chars (date part)
    }
    
    private func flagEmoji(for regionCode: String) -> String {
        // Convert region codes to flag emojis
        let regionMappings: [String: String] = [
            // Common ROM region codes
            "USA": "🇺🇸", "US": "🇺🇸", "NTSC": "🇺🇸",
            "Europe": "🇪🇺", "EUR": "🇪🇺", "PAL": "🇪🇺",
            "Japan": "🇯🇵", "JPN": "🇯🇵", "JP": "🇯🇵",
            "Germany": "🇩🇪", "GER": "🇩🇪", "DE": "🇩🇪",
            "France": "🇫🇷", "FR": "🇫🇷", "FRA": "🇫🇷",
            "Spain": "🇪🇸", "ES": "🇪🇸", "ESP": "🇪🇸",
            "Italy": "🇮🇹", "IT": "🇮🇹", "ITA": "🇮🇹",
            "UK": "🇬🇧", "GB": "🇬🇧", "United Kingdom": "🇬🇧",
            "Canada": "🇨🇦", "CA": "🇨🇦", "CAN": "🇨🇦",
            "Australia": "🇦🇺", "AU": "🇦🇺", "AUS": "🇦🇺",
            "Korea": "🇰🇷", "KR": "🇰🇷", "KOR": "🇰🇷",
            "Brazil": "🇧🇷", "BR": "🇧🇷", "BRA": "🇧🇷",
            "World": "🌍", "WW": "🌍", "WORLD": "🌍"
        ]
        
        return regionMappings[regionCode] ?? "🌍"
    }
    
    private func languageEmoji(for languageCode: String) -> String {
        // Convert language codes to flag emojis
        let languageMappings: [String: String] = [
            "English": "🇬🇧", "EN": "🇬🇧", "en": "🇬🇧",
            "German": "🇩🇪", "DE": "🇩🇪", "de": "🇩🇪",
            "French": "🇫🇷", "FR": "🇫🇷", "fr": "🇫🇷",
            "Spanish": "🇪🇸", "ES": "🇪🇸", "es": "🇪🇸",
            "Italian": "🇮🇹", "IT": "🇮🇹", "it": "🇮🇹",
            "Japanese": "🇯🇵", "JP": "🇯🇵", "ja": "🇯🇵",
            "Korean": "🇰🇷", "KR": "🇰🇷", "ko": "🇰🇷",
            "Portuguese": "🇵🇹", "PT": "🇵🇹", "pt": "🇵🇹",
            "Dutch": "🇳🇱", "NL": "🇳🇱", "nl": "🇳🇱",
            "Russian": "🇷🇺", "RU": "🇷🇺", "ru": "🇷🇺",
            "Chinese": "🇨🇳", "CN": "🇨🇳", "zh": "🇨🇳",
            "Swedish": "🇸🇪", "SE": "🇸🇪", "sv": "🇸🇪",
            "Norwegian": "🇳🇴", "NO": "🇳🇴", "nb": "🇳🇴",
            "Finnish": "🇫🇮", "FI": "🇫🇮", "fi": "🇫🇮",
            "Danish": "🇩🇰", "DK": "🇩🇰", "da": "🇩🇰"
        ]
        
        return languageMappings[languageCode] ?? "🗣️"
    }
}

#Preview {
    NavigationView {
        RomListWithSectionIndex(
            roms: [
                Rom(id: 1, name: "Super Mario Odyssey", platformId: 1, releaseYear: 2017),
                Rom(id: 2, name: "The Legend of Zelda", platformId: 1, releaseYear: 2017),
                Rom(id: 3, name: "Animal Crossing", platformId: 1, releaseYear: 2020),
                Rom(id: 4, name: "Metroid Dread", platformId: 1, releaseYear: 2021)
            ],
            viewMode: .table,
            onRefresh: { },
            onLoadMore: { },
            charIndex: [:],
            selectedChar: nil,
            onCharTapped: { _ in },
            onSort: { _, _ in },
            currentOrderBy: "name",
            currentOrderDir: "asc",
            canLoadMore: false,
            platform: Platform(id: 1, name: "Nintendo Switch", slug: "nintendo-switch", romCount: 4)
        )
    }
}
