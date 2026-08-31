//
//  Logger.swift
//  romm
//
//  Created by Ilyas Hallak on 13.08.25.
//

import Foundation
import os

// MARK: - Log Configuration

enum LogLevel: Int, CaseIterable, Codable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4
    case critical = 5

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .notice: return "📢"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "💥"
        }
    }
}

enum LogCategory: String, CaseIterable, Codable {
    case network = "Network"
    case ui = "UI"
    case data = "Data"
    case auth = "Authentication"
    case performance = "Performance"
    case general = "General"
    case manual = "Manual"
    case viewModel = "ViewModel"
    case sync = "Sync"
}

class LogConfiguration: ObservableObject {
    static let shared = LogConfiguration()

    /// Logging global aktivieren/deaktivieren
    @Published var isLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLoggingEnabled, forKey: "logging.enabled")
        }
    }

    @Published private var categoryLevels: [LogCategory: LogLevel] = [:]
    @Published var globalMinLevel: LogLevel = .debug
    @Published var showPerformanceLogs = true
    @Published var showTimestamps = true
    @Published var includeSourceLocation = true

    private init() {
        // In Debug-Builds: Logging automatisch aktiviert
        // In Release-Builds: Nur wenn manuell aktiviert
        #if DEBUG
        self.isLoggingEnabled = UserDefaults.standard.object(forKey: "logging.enabled") as? Bool ?? true
        #else
        self.isLoggingEnabled = UserDefaults.standard.object(forKey: "logging.enabled") as? Bool ?? false
        #endif
        loadConfiguration()
    }
    
    func setLevel(_ level: LogLevel, for category: LogCategory) {
        categoryLevels[category] = level
        saveConfiguration()
    }
    
    func getLevel(for category: LogCategory) -> LogLevel {
        return categoryLevels[category] ?? globalMinLevel
    }
    
    func shouldLog(_ level: LogLevel, for category: LogCategory) -> Bool {
        // Erst prüfen ob Logging global aktiviert ist
        guard isLoggingEnabled else { return false }

        // Performance-Logs extra behandeln
        if category == .performance && !showPerformanceLogs {
            return false
        }

        let categoryLevel = getLevel(for: category)
        return level.rawValue >= categoryLevel.rawValue
    }
    
    private func loadConfiguration() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "LogConfiguration"),
           let config = try? JSONDecoder().decode([String: Int].self, from: data) {
            for (categoryString, levelInt) in config {
                if let category = LogCategory(rawValue: categoryString),
                   let level = LogLevel(rawValue: levelInt) {
                    categoryLevels[category] = level
                }
            }
        }
        
        globalMinLevel = LogLevel(rawValue: UserDefaults.standard.integer(forKey: "LogGlobalLevel")) ?? .debug
        showPerformanceLogs = (UserDefaults.standard.object(forKey: "LogShowPerformance") as? Bool) ?? true
        showTimestamps = (UserDefaults.standard.object(forKey: "LogShowTimestamps") as? Bool) ?? true
        includeSourceLocation = (UserDefaults.standard.object(forKey: "LogIncludeSourceLocation") as? Bool) ?? true
    }
    
    private func saveConfiguration() {
        let config = categoryLevels.mapKeys { $0.rawValue }.mapValues { $0.rawValue }
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "LogConfiguration")
        }
        
        UserDefaults.standard.set(globalMinLevel.rawValue, forKey: "LogGlobalLevel")
        UserDefaults.standard.set(showPerformanceLogs, forKey: "LogShowPerformance")
        UserDefaults.standard.set(showTimestamps, forKey: "LogShowTimestamps")
        UserDefaults.standard.set(includeSourceLocation, forKey: "LogIncludeSourceLocation")
    }
}

struct Logger {
    private let logger: os.Logger
    private let category: LogCategory
    private let config = LogConfiguration.shared
    
    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.romm.app", category: LogCategory) {
        self.logger = os.Logger(subsystem: subsystem, category: category.rawValue)
        self.category = category
    }
    
    // MARK: - Log Levels

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard config.shouldLog(.debug, for: category) else { return }
        let formattedMessage = formatMessage(message, level: .debug, file: file, function: function, line: line)
        logger.debug("\(formattedMessage)")

        // In LogStore speichern
        let entry = LogEntry(level: .debug, category: category, message: message, file: file, function: function, line: line)
        Task {
            await LogStore.shared.addEntry(entry)
        }
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard config.shouldLog(.info, for: category) else { return }
        let formattedMessage = formatMessage(message, level: .info, file: file, function: function, line: line)
        logger.info("\(formattedMessage)")

        // In LogStore speichern
        let entry = LogEntry(level: .info, category: category, message: message, file: file, function: function, line: line)
        Task {
            await LogStore.shared.addEntry(entry)
        }
    }
    
    func notice(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard config.shouldLog(.notice, for: category) else { return }
        let formattedMessage = formatMessage(message, level: .notice, file: file, function: function, line: line)
        logger.notice("\(formattedMessage)")

        // In LogStore speichern
        let entry = LogEntry(level: .notice, category: category, message: message, file: file, function: function, line: line)
        Task {
            await LogStore.shared.addEntry(entry)
        }
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard config.shouldLog(.warning, for: category) else { return }
        let formattedMessage = formatMessage(message, level: .warning, file: file, function: function, line: line)
        logger.warning("\(formattedMessage)")

        // In LogStore speichern
        let entry = LogEntry(level: .warning, category: category, message: message, file: file, function: function, line: line)
        Task {
            await LogStore.shared.addEntry(entry)
        }
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard config.shouldLog(.error, for: category) else { return }
        let formattedMessage = formatMessage(message, level: .error, file: file, function: function, line: line)
        logger.error("\(formattedMessage)")

        // In LogStore speichern
        let entry = LogEntry(level: .error, category: category, message: message, file: file, function: function, line: line)
        Task {
            await LogStore.shared.addEntry(entry)
        }
    }
    
    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard config.shouldLog(.critical, for: category) else { return }
        let formattedMessage = formatMessage(message, level: .critical, file: file, function: function, line: line)
        logger.critical("\(formattedMessage)")

        // In LogStore speichern
        let entry = LogEntry(level: .critical, category: category, message: message, file: file, function: function, line: line)
        Task {
            await LogStore.shared.addEntry(entry)
        }
    }
    
    // MARK: - Convenience Methods
    
    func logNetworkRequest(method: String, url: String, statusCode: Int? = nil) {
        guard config.shouldLog(.info, for: category) else { return }
        if let statusCode = statusCode {
            info("🌐 \(method) \(url) - Status: \(statusCode)")
        } else {
            info("🌐 \(method) \(url)")
        }
    }
    
    func logNetworkError(method: String, url: String, error: Error) {
        guard config.shouldLog(.error, for: category) else { return }
        self.error("❌ \(method) \(url) - Error: \(error.localizedDescription)")
    }
    
    func logPerformance(_ operation: String, duration: TimeInterval) {
        guard config.showPerformanceLogs && config.shouldLog(.info, for: category) else { return }
        info("⏱️ \(operation) completed in \(String(format: "%.3f", duration))s")
    }
    
    // MARK: - Private Helpers
    
    private func formatMessage(_ message: String, level: LogLevel, file: String, function: String, line: Int) -> String {
        var components: [String] = []
        
        if config.showTimestamps {
            let timestamp = DateFormatter.logTimestamp.string(from: Date())
            components.append(timestamp)
        }
        
        components.append(level.emoji)
        components.append("[\(category.rawValue)]")
        
        if config.includeSourceLocation {
            components.append("[\(sourceFileName(filePath: file)):\(line)]")
            components.append(function)
        }
        
        components.append("-")
        components.append(message)
        
        return components.joined(separator: " ")
    }
    
    private func sourceFileName(filePath: String) -> String {
        return URL(fileURLWithPath: filePath).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
    }
}

// MARK: - Category-specific Loggers

extension Logger {
    static let network = Logger(category: .network)
    static let ui = Logger(category: .ui)
    static let data = Logger(category: .data)
    static let auth = Logger(category: .auth)
    static let performance = Logger(category: .performance)
    static let general = Logger(category: .general)
    static let manual = Logger(category: .manual)
    static let viewModel = Logger(category: .viewModel)
    static let sync = Logger(category: .sync)
}

// MARK: - Performance Measurement Helper

struct PerformanceMeasurement {
    private let startTime = CFAbsoluteTimeGetCurrent()
    private let operation: String
    private let logger: Logger
    
    init(operation: String, logger: Logger = .performance) {
        self.operation = operation
        self.logger = logger
        logger.debug("🚀 Starting \(operation)")
    }
    
    func end() {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance(operation, duration: duration)
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        
        return formatter
    }()
}

// MARK: - Dictionary Extension

extension Dictionary {
    func mapKeys<T>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        return try Dictionary<T, Value>(uniqueKeysWithValues: map { (try transform($0.key), $0.value) })
    }
}
