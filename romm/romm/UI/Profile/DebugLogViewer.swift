//
//  DebugLogViewer.swift
//  romm
//
//  Created by Ilyas Hallak on 13.08.25.
//

import SwiftUI

/// SwiftUI Viewer for all log entries with filter, search and export
struct DebugLogViewer: View {
    @StateObject private var config = LogConfiguration.shared
    @State private var entries: [LogEntry] = []
    @State private var searchText = ""
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var selectedCategories: Set<LogCategory> = Set(LogCategory.allCases)
    @State private var showingFilters = false
    @State private var showingExportOptions = false
    @State private var autoScroll = true

    var filteredEntries: [LogEntry] {
        var filtered = entries

        // Nach Suchtext filtern
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            filtered = filtered.filter { entry in
                entry.message.lowercased().contains(lowercasedSearch) ||
                entry.file.lowercased().contains(lowercasedSearch) ||
                entry.function.lowercased().contains(lowercasedSearch)
            }
        }

        // Nach Log-Levels filtern
        if !selectedLevels.isEmpty && selectedLevels.count < LogLevel.allCases.count {
            filtered = filtered.filter { selectedLevels.contains($0.level) }
        }

        // Nach Kategorien filtern
        if !selectedCategories.isEmpty && selectedCategories.count < LogCategory.allCases.count {
            filtered = filtered.filter { selectedCategories.contains($0.category) }
        }

        return filtered
    }

    var body: some View {
        VStack(spacing: 0) {
            if !config.isLoggingEnabled {
                // Banner wenn Logging deaktiviert
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Logging is disabled")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Enable logging in settings to collect logs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                // Empty State
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Logs Available")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Once the app generates logs, they will be displayed here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                logListView
            }
        }
        .navigationTitle("Log Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search logs...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        showingExportOptions = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Toggle(isOn: $autoScroll) {
                        Label("Auto-Scroll", systemImage: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task {
                            await LogStore.shared.clear()
                        }
                    } label: {
                        Label("Clear All Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            LogFilterView(
                selectedLevels: $selectedLevels,
                selectedCategories: $selectedCategories
            )
        }
        .sheet(isPresented: $showingExportOptions) {
            LogExportView(entries: filteredEntries)
        }
        .onAppear {
            loadEntries()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            // Refresh entries periodically
            loadEntries()
        }
    }

    @ViewBuilder
    private var logListView: some View {
        VStack(spacing: 0) {
            // Stats Header
            statsHeader

            // Log List mit Auto-Scroll
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry, showDetails: config.includeSourceLocation)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .id(entry.id)
                    }
                }
                .listStyle(.plain)
                .onChange(of: filteredEntries.count) { _, _ in
                    if autoScroll, let lastEntry = filteredEntries.last {
                        withAnimation {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var statsHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(entries.count)")
                    .font(.headline)
            }

            Divider()
                .frame(height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Filtered")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(filteredEntries.count)")
                    .font(.headline)
            }

            Spacer()

            // Active Filter Pills
            if !selectedLevels.isEmpty && selectedLevels.count < LogLevel.allCases.count {
                HStack(spacing: 4) {
                    ForEach(Array(selectedLevels.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { level in
                        Text(level.emoji)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func loadEntries() {
        Task {
            entries = await LogStore.shared.getEntries()
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    let showDetails: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header mit Time + Level + Category
            HStack(spacing: 8) {
                Text(timeString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(entry.level.emoji)

                Text(categoryEmoji)

                Spacer()

                if showDetails {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Message
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(levelColor)

            // Details (expandable)
            if isExpanded && showDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()

                    LogDetailRow(label: "File", value: entry.file)
                    LogDetailRow(label: "Function", value: entry.function)
                    LogDetailRow(label: "Line", value: "\(entry.line)")
                    LogDetailRow(label: "Category", value: entry.category.rawValue)
                    LogDetailRow(label: "Level", value: levelName)
                }
                .font(.caption)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: entry.timestamp)
    }

    private var categoryEmoji: String {
        switch entry.category {
        case .network: return "🌐"
        case .ui: return "🎨"
        case .data: return "🗃️"
        case .auth: return "🔐"
        case .performance: return "⚡"
        case .general: return "📦"
        case .manual: return "📚"
        case .viewModel: return "🔄"
        case .sync: return "🔄"
        case .emulator: return "🎮"
        }
    }

    private var levelName: String {
        switch entry.level {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info: return .primary
        case .notice: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return Color(red: 0.8, green: 0, blue: 0)
        }
    }
}

struct LogDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Text(value)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Filter View

struct LogFilterView: View {
    @Binding var selectedLevels: Set<LogLevel>
    @Binding var selectedCategories: Set<LogCategory>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Toggle(isOn: Binding(
                            get: { selectedLevels.contains(level) },
                            set: { isSelected in
                                if isSelected {
                                    selectedLevels.insert(level)
                                } else {
                                    selectedLevels.remove(level)
                                }
                            }
                        )) {
                            HStack {
                                Text(level.emoji)
                                Text(levelName(for: level))
                            }
                        }
                    }

                    Button("Select All") {
                        selectedLevels = Set(LogLevel.allCases)
                    }

                    Button("Select None") {
                        selectedLevels.removeAll()
                    }
                } header: {
                    Text("Log Levels")
                }

                Section {
                    ForEach(LogCategory.allCases, id: \.self) { category in
                        Toggle(isOn: Binding(
                            get: { selectedCategories.contains(category) },
                            set: { isSelected in
                                if isSelected {
                                    selectedCategories.insert(category)
                                } else {
                                    selectedCategories.remove(category)
                                }
                            }
                        )) {
                            HStack {
                                Text(categoryEmoji(for: category))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.rawValue)
                                    Text(categoryDescription(for: category))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button("Select All") {
                        selectedCategories = Set(LogCategory.allCases)
                    }

                    Button("Select None") {
                        selectedCategories.removeAll()
                    }
                } header: {
                    Text("Categories")
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func levelName(for level: LogLevel) -> String {
        switch level {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        }
    }

    private func categoryEmoji(for category: LogCategory) -> String {
        switch category {
        case .network: return "🌐"
        case .ui: return "🎨"
        case .data: return "🗃️"
        case .auth: return "🔐"
        case .performance: return "⚡"
        case .general: return "📦"
        case .manual: return "📚"
        case .viewModel: return "🔄"
        case .sync: return "🔄"
        case .emulator: return "🎮"
        }
    }

    private func categoryDescription(for category: LogCategory) -> String {
        switch category {
        case .network: return "Network operations, API calls"
        case .ui: return "User interface, view updates"
        case .data: return "Data operations, repository"
        case .auth: return "Authentication, login"
        case .performance: return "Performance metrics, timing"
        case .general: return "General logic, use cases"
        case .manual: return "PDF manual system"
        case .viewModel: return "View model layer, state"
        case .sync: return "Synchronization operations"
        case .emulator: return "Launching games, ROM resolution, external apps"
        }
    }
}

// MARK: - Export View

struct LogExportView: View {
    let entries: [LogEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var shareItem: ShareItem?

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        exportAsText()
                    } label: {
                        Label("Export as Text", systemImage: "doc.text")
                    }

                    Button {
                        exportAsJSON()
                    } label: {
                        Label("Export as JSON", systemImage: "curlybraces")
                    }

                    Button {
                        exportAsZIP()
                    } label: {
                        Label("Export as ZIP", systemImage: "doc.zipper")
                    }
                } header: {
                    Text("Export Format")
                } footer: {
                    Text("\(entries.count) log entries will be exported")
                }
            }
            .navigationTitle("Export Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                LogShareSheet(url: item.url)
            }
        }
    }

    private func exportAsText() {
        Task {
            let text = await LogStore.shared.exportAsText()
            guard let data = text.data(using: .utf8) else { return }

            let url = saveToTempFile(data: data, filename: "romm_logs_\(timestamp()).txt")
            await MainActor.run {
                shareItem = ShareItem(url: url)
            }
        }
    }

    private func exportAsJSON() {
        Task {
            // JSON export: Create a simple JSON structure from logs
            let text = await LogStore.shared.exportAsText()

            // Create a simple JSON wrapper
            let jsonDict: [String: Any] = [
                "timestamp": timestamp(),
                "total_entries": entries.count,
                "logs": text
            ]

            guard let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted) else { return }

            let url = saveToTempFile(data: data, filename: "romm_logs_\(timestamp()).json")
            await MainActor.run {
                shareItem = ShareItem(url: url)
            }
        }
    }

    private func exportAsZIP() {
        Task {
            guard let (data, filename) = try? await LogStore.shared.exportAsZippedData() else { return }

            let url = saveToTempFile(data: data, filename: filename)
            await MainActor.run {
                shareItem = ShareItem(url: url)
            }
        }
    }

    private func saveToTempFile(data: Data, filename: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        try? data.write(to: fileURL)

        return fileURL
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

// MARK: - Log Share Sheet

struct LogShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DebugLogViewer()
    }
}
