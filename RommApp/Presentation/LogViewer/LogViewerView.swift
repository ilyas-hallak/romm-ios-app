// SPDX-License-Identifier: MIT

import SwiftUI

/// Log-Viewer mit Such- und Filterfunktionen
struct LogViewerView: View {
    @StateObject private var store = LogStore.shared
    @StateObject private var config = LogConfiguration.shared

    @State private var searchText = ""
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var selectedCategories: Set<LogCategory> = Set(LogCategory.allCases)
    @State private var showingFilters = false
    @State private var showingExportOptions = false
    @State private var autoScroll = true

    var filteredEntries: [LogEntry] {
        store.filter(
            searchText: searchText,
            levels: selectedLevels.isEmpty ? nil : selectedLevels,
            categories: selectedCategories.isEmpty ? nil : selectedCategories
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !config.isLoggingEnabled {
                ContentUnavailableView(
                    "Logging ist deaktiviert",
                    systemImage: "xmark.circle",
                    description: Text("Aktiviere Logging in den Einstellungen um Logs zu sammeln.")
                )
            } else if store.entries.isEmpty {
                ContentUnavailableView(
                    "Keine Logs vorhanden",
                    systemImage: "tray",
                    description: Text("Sobald die App Logs erzeugt, werden sie hier angezeigt.")
                )
            } else {
                logListView
            }
        }
        .navigationTitle("Log-Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Logs durchsuchen...")
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
                        Label("Exportieren", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Alle Logs löschen", systemImage: "trash")
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
    }

    @ViewBuilder
    private var logListView: some View {
        VStack(spacing: 0) {
            // Stats Header
            statsHeader

            // Log List
            List {
                ForEach(filteredEntries) { entry in
                    LogEntryRow(entry: entry, showDetails: config.includeSourceLocation)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
            .listStyle(.plain)
        }
    }

    private var statsHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Logs gesamt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(store.entries.count)")
                    .font(.headline)
            }

            Divider()
                .frame(height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Gefiltert")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(filteredEntries.count)")
                    .font(.headline)
            }

            Spacer()

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

                Text(entry.category.emoji)

                Spacer()

                if showDetails {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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

                    DetailRow(label: "Datei", value: entry.file)
                    DetailRow(label: "Funktion", value: entry.function)
                    DetailRow(label: "Zeile", value: "\(entry.line)")
                    DetailRow(label: "Kategorie", value: entry.category.rawValue)
                    DetailRow(label: "Level", value: entry.level.rawValue)
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

struct DetailRow: View {
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
                                Text(level.rawValue)
                            }
                        }
                    }

                    Button("Alle auswählen") {
                        selectedLevels = Set(LogLevel.allCases)
                    }

                    Button("Keine auswählen") {
                        selectedLevels.removeAll()
                    }
                } header: {
                    Text("Log-Levels")
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
                                Text(category.emoji)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.rawValue)
                                    Text(category.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button("Alle auswählen") {
                        selectedCategories = Set(LogCategory.allCases)
                    }

                    Button("Keine auswählen") {
                        selectedCategories.removeAll()
                    }
                } header: {
                    Text("Kategorien")
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Export View

struct LogExportView: View {
    let entries: [LogEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var exportData: ExportData?

    struct ExportData: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
        let mimeType: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        exportAsText()
                    } label: {
                        Label("Als Text exportieren", systemImage: "doc.text")
                    }

                    Button {
                        exportAsJSON()
                    } label: {
                        Label("Als JSON exportieren", systemImage: "curlybraces")
                    }
                } header: {
                    Text("Export-Format")
                } footer: {
                    Text("\(entries.count) Log-Einträge werden exportiert")
                }
            }
            .navigationTitle("Logs exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $exportData) { data in
                ShareSheet(items: [data.data])
            }
        }
    }

    private func exportAsText() {
        let text = entries.map { $0.formattedString }.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "romm_logs_\(timestamp).txt"

        exportData = ExportData(data: data, filename: filename, mimeType: "text/plain")
    }

    private func exportAsJSON() {
        guard let data = LogStore.shared.exportAsJSON() else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "romm_logs_\(timestamp).json"

        exportData = ExportData(data: data, filename: filename, mimeType: "application/json")
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LogViewerView()
    }
}
