//
//  LoggingConfigurationView.swift
//  romm
//
//  Created by Ilyas Hallak on 13.08.25.
//

import SwiftUI
import os

/// Settings UI for the logging system
struct LoggingConfigurationView: View {
    @StateObject private var config = LogConfiguration.shared
    private let logger = Logger.ui

    var body: some View {
        Form {
            // MARK: - Master Toggle
            Section {
                Toggle("Enable Logging", isOn: $config.isLoggingEnabled)
                    .font(.headline)

                if !config.isLoggingEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                        Text("Logging is disabled. No logs will be collected.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Logging")
            } footer: {
                Text("When disabled, no logs will be collected and the system has no performance impact.")
            }

            if config.isLoggingEnabled {
                // MARK: - Global Settings
                Section {
                    Picker("Global Level", selection: $config.globalMinLevel) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text("\(level.emoji) \(levelName(for: level))")
                                .tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Global Settings")
                } footer: {
                    Text("Base level for the entire app. All categories use at least this level.")
                }

                // MARK: - Categories
                Section {
                    ForEach(LogCategory.allCases, id: \.self) { category in
                        Picker(selection: Binding(
                            get: { config.getLevel(for: category) },
                            set: { config.setLevel($0, for: category) }
                        )) {
                            ForEach(LogLevel.allCases, id: \.self) { level in
                                Text("\(level.emoji) \(levelName(for: level))")
                                    .tag(level)
                            }
                        } label: {
                            HStack {
                                Text(categoryEmoji(for: category))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.rawValue)
                                        .font(.body)
                                    Text(categoryDescription(for: category))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Select the log level for each category.")
                }

                // MARK: - Display Options
                Section {
                    Toggle("Show performance logs", isOn: $config.showPerformanceLogs)
                    Toggle("Show timestamps", isOn: $config.showTimestamps)
                    Toggle("Show source location", isOn: $config.includeSourceLocation)
                } header: {
                    Text("Display Options")
                } footer: {
                    Text("These options affect the formatting of log outputs.")
                }

                // MARK: - Log Viewer
                Section {
                    NavigationLink {
                        DebugLogViewer()
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                            Text("Open Log Viewer")
                        }
                    }
                } header: {
                    Text("View Logs")
                } footer: {
                    Text("View all collected logs with filter and export functions.")
                }

                // MARK: - Reset
                Section {
                    Button(role: .destructive) {
                        resetToDefaults()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                    }
                } footer: {
                    Text("Resets all logging settings to default values (logging disabled, all levels set to Debug).")
                }
            }
        }
        .navigationTitle("Logging Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            logger.debug("Opened logging configuration view")
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
        }
    }

    private func categoryDescription(for category: LogCategory) -> String {
        switch category {
        case .network: return String(localized: "Network operations, API calls")
        case .ui: return String(localized: "User interface, view updates")
        case .data: return String(localized: "Data operations, repository")
        case .auth: return String(localized: "Authentication, login")
        case .performance: return String(localized: "Performance metrics, timing")
        case .general: return String(localized: "General logic, use cases")
        case .manual: return String(localized: "PDF manual system")
        case .viewModel: return String(localized: "View model layer, state")
        case .sync: return String(localized: "Synchronization operations")
        }
    }

    private func resetToDefaults() {
        logger.info("Resetting logging configuration to defaults")

        // Reset all category levels
        for category in LogCategory.allCases {
            config.setLevel(.debug, for: category)
        }

        // Reset global settings
        config.globalMinLevel = .debug
        config.showPerformanceLogs = true
        config.showTimestamps = true
        config.includeSourceLocation = true
        config.isLoggingEnabled = false

        logger.info("Logging configuration reset to defaults")
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
                                Text(levelName(for: level))
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
                Text("Select Log Level")
            } footer: {
                Text("Higher levels show fewer logs. Debug shows everything, Critical shows only critical messages.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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

    private func levelDescription(for level: LogLevel) -> String {
        switch level {
        case .debug:
            return "Shows all log messages"
        case .info:
            return "Shows Info and higher"
        case .notice:
            return "Shows notable events and higher"
        case .warning:
            return "Shows only warnings, errors and critical"
        case .error:
            return "Shows only errors and critical"
        case .critical:
            return "Shows only critical system messages"
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
                    Text("Category")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(categoryEmoji)
                    Text(category.rawValue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(categoryDescription)
                }
            }

            Section {
                NavigationLink {
                    LogLevelPickerView(
                        title: "\(category.rawValue) Log Level",
                        selectedLevel: Binding(
                            get: { config.getLevel(for: category) },
                            set: { config.setLevel($0, for: category) }
                        ),
                        description: "Select the minimum log level for \(category.rawValue) logs."
                    )
                } label: {
                    HStack {
                        Text("Log Level")
                        Spacer()
                        let level = config.getLevel(for: category)
                        Text(levelName(for: level))
                            .foregroundColor(.secondary)
                        Text(level.emoji)
                    }
                }
            } header: {
                Text("Settings")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Log Level Hierarchy:")
                        .font(.headline)

                    Text("Debug < Info < Notice < Warning < Error < Critical")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("A higher level shows fewer logs. For example, if you choose 'Warning', you will only see Warning, Error and Critical logs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Help")
            }
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var categoryEmoji: String {
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
        }
    }

    private var categoryDescription: String {
        switch category {
        case .network: return String(localized: "Network operations and API calls")
        case .ui: return String(localized: "User interface and view updates")
        case .data: return String(localized: "Data operations and repositories")
        case .auth: return String(localized: "Authentication and login")
        case .performance: return String(localized: "Performance metrics and timing")
        case .general: return String(localized: "General logic and use cases")
        case .manual: return String(localized: "PDF manual system")
        case .viewModel: return String(localized: "View model layer and state")
        case .sync: return String(localized: "Synchronization operations")
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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LoggingConfigurationView()
    }
}
