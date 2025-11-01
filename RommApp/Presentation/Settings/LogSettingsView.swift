// SPDX-License-Identifier: MIT

import SwiftUI

/// Einstellungen für das Logging-System
struct LogSettingsView: View {
    @StateObject private var config = LogConfiguration.shared
    @State private var showingCategoryDetail: LogCategory?

    var body: some View {
        Form {
            // MARK: - Master Toggle
            Section {
                Toggle("Logging aktivieren", isOn: $config.isLoggingEnabled)
                    .font(.headline)

                if !config.isLoggingEnabled {
                    Text("Logging ist deaktiviert. Keine Logs werden gesammelt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Logging")
            } footer: {
                Text("Wenn deaktiviert, werden keine Logs gesammelt und das System hat keine Performance-Auswirkungen.")
            }

            if config.isLoggingEnabled {
                // MARK: - Global Settings
                Section {
                    NavigationLink {
                        LogLevelPickerView(
                            title: "Globales Log-Level",
                            selectedLevel: $config.globalMinimumLevel,
                            description: "Basis-Level für die gesamte App. Alle Kategorien verwenden mindestens dieses Level."
                        )
                    } label: {
                        HStack {
                            Text("Globales Level")
                            Spacer()
                            Text(config.globalMinimumLevel.rawValue)
                                .foregroundColor(.secondary)
                            Text(config.globalMinimumLevel.emoji)
                        }
                    }
                } header: {
                    Text("Globale Einstellungen")
                }

                // MARK: - Categories
                Section {
                    ForEach(LogCategory.allCases, id: \.self) { category in
                        NavigationLink {
                            CategoryDetailView(category: category)
                        } label: {
                            HStack {
                                Text(category.emoji)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.rawValue)
                                        .font(.body)
                                    Text(category.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(config.categoryLevels[category]?.rawValue ?? "Debug")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Kategorien")
                } footer: {
                    Text("Tippe auf eine Kategorie um das spezifische Log-Level anzupassen.")
                }

                // MARK: - Display Options
                Section {
                    Toggle("Performance-Logs anzeigen", isOn: $config.showPerformanceLogs)
                    Toggle("Zeitstempel anzeigen", isOn: $config.showTimestamps)
                    Toggle("Quellenangabe anzeigen", isOn: $config.includeSourceLocation)
                } header: {
                    Text("Anzeige-Optionen")
                }

                // MARK: - Log Viewer
                Section {
                    NavigationLink("Log-Viewer öffnen") {
                        LogViewerView()
                    }
                } header: {
                    Text("Logs anzeigen")
                }

                // MARK: - Reset
                Section {
                    Button(role: .destructive) {
                        config.resetToDefaults()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Auf Standard zurücksetzen")
                        }
                    }
                } footer: {
                    Text("Setzt alle Log-Einstellungen auf die Standardwerte zurück (Logging deaktiviert, alle Level auf Debug).")
                }
            }
        }
        .navigationTitle("Logging-Konfiguration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Log Level Picker View

struct LogLevelPickerView: View {
    let title: String
    @Binding var selectedLevel: LogLevel
    let description: String?

    init(
        title: String,
        selectedLevel: Binding<LogLevel>,
        description: String? = nil
    ) {
        self.title = title
        self._selectedLevel = selectedLevel
        self.description = description
    }

    var body: some View {
        Form {
            if let description = description {
                Section {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Button {
                        selectedLevel = level
                    } label: {
                        HStack {
                            Text(level.emoji)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.rawValue)
                                    .foregroundColor(.primary)
                                Text(levelDescription(for: level))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedLevel == level {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("Log-Level wählen")
            } footer: {
                Text("Höhere Levels zeigen weniger Logs. Debug zeigt alles, Critical nur kritische Meldungen.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func levelDescription(for level: LogLevel) -> String {
        switch level {
        case .debug:
            return "Zeigt alle Log-Nachrichten"
        case .info:
            return "Zeigt Info und höher"
        case .notice:
            return "Zeigt bemerkenswerte Ereignisse und höher"
        case .warning:
            return "Zeigt nur Warnungen, Fehler und Critical"
        case .error:
            return "Zeigt nur Fehler und Critical"
        case .critical:
            return "Zeigt nur kritische System-Meldungen"
        }
    }
}

// MARK: - Category Detail View

struct CategoryDetailView: View {
    let category: LogCategory
    @StateObject private var config = LogConfiguration.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Kategorie")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(category.emoji)
                    Text(category.rawValue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beschreibung")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(category.description)
                }
            }

            Section {
                NavigationLink {
                    LogLevelPickerView(
                        title: "\(category.rawValue) Log-Level",
                        selectedLevel: Binding(
                            get: { config.categoryLevels[category] ?? .debug },
                            set: { config.setLevel($0, for: category) }
                        ),
                        description: "Wähle das Minimum Log-Level für \(category.rawValue)-Logs."
                    )
                } label: {
                    HStack {
                        Text("Log-Level")
                        Spacer()
                        let level = config.categoryLevels[category] ?? .debug
                        Text(level.rawValue)
                            .foregroundColor(.secondary)
                        Text(level.emoji)
                    }
                }
            } header: {
                Text("Einstellungen")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Log-Level Hierarchie:")
                        .font(.headline)

                    Text("Debug < Info < Notice < Warning < Error < Critical")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("Ein höheres Level zeigt weniger Logs. Wenn du zum Beispiel 'Warning' wählst, siehst du nur Warning-, Error- und Critical-Logs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Hilfe")
            }
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LogSettingsView()
    }
}
