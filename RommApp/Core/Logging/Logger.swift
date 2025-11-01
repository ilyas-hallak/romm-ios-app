// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Haupt-Logger-Klasse für strukturiertes Logging
class Logger {
    private let category: LogCategory
    private let osLog: OSLog
    private let config: LogConfiguration

    // MARK: - Static Logger Instances

    /// Logger für Netzwerk-Operationen
    static let network = Logger(category: .network)

    /// Logger für UI-Komponenten
    static let ui = Logger(category: .ui)

    /// Logger für Daten-Operationen
    static let data = Logger(category: .data)

    /// Logger für Authentifizierung
    static let auth = Logger(category: .auth)

    /// Logger für Performance-Messungen
    static let performance = Logger(category: .performance)

    /// Logger für allgemeine Logik
    static let general = Logger(category: .general)

    /// Logger für Manual/PDF-System
    static let manual = Logger(category: .manual)

    /// Logger für ViewModels
    static let viewModel = Logger(category: .viewModel)

    // MARK: - Initialization

    private init(category: LogCategory) {
        self.category = category
        self.config = LogConfiguration.shared
        self.osLog = OSLog(subsystem: "com.romm.app", category: category.rawValue)
    }

    // MARK: - Logging Methods

    /// Debug-Level Logging
    func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    /// Info-Level Logging
    func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    /// Notice-Level Logging
    func notice(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .notice, message: message, file: file, function: function, line: line)
    }

    /// Warning-Level Logging
    func warning(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }

    /// Error-Level Logging
    func error(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    /// Critical-Level Logging
    func critical(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .critical, message: message, file: file, function: function, line: line)
    }

    // MARK: - Core Logging Method

    private func log(
        level: LogLevel,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
        // Prüfen ob geloggt werden soll
        guard config.shouldLog(level, for: category) else { return }

        // LogEntry erstellen
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line
        )

        // In LogStore speichern
        LogStore.shared.add(entry)

        // An OSLog senden
        os_log(
            "%{public}@",
            log: osLog,
            type: level.osLogType,
            entry.formattedString
        )
    }

    // MARK: - Convenience Methods

    /// Loggt einen Netzwerk-Request
    func logNetworkRequest(
        method: String,
        url: String,
        statusCode: Int? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let statusString = statusCode.map { " - Status: \($0)" } ?? ""
        let message = "\(method) \(url)\(statusString)"
        info(message, file: file, function: function, line: line)
    }

    /// Loggt einen Netzwerk-Fehler
    func logNetworkError(
        method: String,
        url: String,
        error: Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let message = "\(method) \(url) - Error: \(error.localizedDescription)"
        self.error(message, file: file, function: function, line: line)
    }

    /// Loggt Performance-Messungen
    func logPerformance(
        _ operation: String,
        duration: TimeInterval,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let message = "\(operation) took \(String(format: "%.3f", duration))s"
        info(message, file: file, function: function, line: line)
    }
}

// MARK: - Performance Measurement Helper

/// Hilfsklasse für Performance-Messungen
class PerformanceMeasurement {
    private let operation: String
    private let logger: Logger
    private let startTime: CFAbsoluteTime
    private let file: String
    private let function: String
    private let line: Int

    init(
        operation: String,
        logger: Logger = .performance,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.operation = operation
        self.logger = logger
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.file = file
        self.function = function
        self.line = line

        logger.debug("⏱️ Starting: \(operation)", file: file, function: function, line: line)
    }

    func end() {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance(operation, duration: duration, file: file, function: function, line: line)
    }

    deinit {
        // Automatisch messen wenn vergessen wurde end() zu rufen
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance(operation, duration: duration, file: file, function: function, line: line)
    }
}
