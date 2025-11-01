// SPDX-License-Identifier: MIT

import Foundation
import Combine

/// Zentrale Konfiguration für das Logging-System
class LogConfiguration: ObservableObject {
    static let shared = LogConfiguration()

    // MARK: - Published Properties

    /// Logging global aktivieren/deaktivieren
    @Published var isLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLoggingEnabled, forKey: "logging.enabled")
        }
    }

    /// Globales Minimum Log-Level
    @Published var globalMinimumLevel: LogLevel {
        didSet {
            UserDefaults.standard.set(globalMinimumLevel.rawValue, forKey: "logging.globalLevel")
        }
    }

    /// Kategorie-spezifische Log-Levels
    @Published var categoryLevels: [LogCategory: LogLevel] {
        didSet {
            saveCategoryLevels()
        }
    }

    /// Performance-Logs anzeigen
    @Published var showPerformanceLogs: Bool {
        didSet {
            UserDefaults.standard.set(showPerformanceLogs, forKey: "logging.showPerformance")
        }
    }

    /// Zeitstempel anzeigen
    @Published var showTimestamps: Bool {
        didSet {
            UserDefaults.standard.set(showTimestamps, forKey: "logging.showTimestamps")
        }
    }

    /// Source-Location anzeigen (Datei:Zeile)
    @Published var includeSourceLocation: Bool {
        didSet {
            UserDefaults.standard.set(includeSourceLocation, forKey: "logging.includeSourceLocation")
        }
    }

    // MARK: - Initialization

    private init() {
        // Logging ist standardmäßig DEAKTIVIERT
        self.isLoggingEnabled = UserDefaults.standard.object(forKey: "logging.enabled") as? Bool ?? false

        // Standard-Werte für andere Einstellungen
        self.globalMinimumLevel = LogLevel(rawValue: UserDefaults.standard.integer(forKey: "logging.globalLevel")) ?? .debug
        self.showPerformanceLogs = UserDefaults.standard.object(forKey: "logging.showPerformance") as? Bool ?? true
        self.showTimestamps = UserDefaults.standard.object(forKey: "logging.showTimestamps") as? Bool ?? true
        self.includeSourceLocation = UserDefaults.standard.object(forKey: "logging.includeSourceLocation") as? Bool ?? true

        // Kategorie-Levels laden
        self.categoryLevels = Self.loadCategoryLevels()
    }

    // MARK: - Methods

    /// Prüft, ob für eine Kategorie und ein Level geloggt werden soll
    func shouldLog(_ level: LogLevel, for category: LogCategory) -> Bool {
        guard isLoggingEnabled else { return false }

        // Performance-Logs extra behandeln
        if category == .performance && !showPerformanceLogs {
            return false
        }

        // Kategorie-spezifisches Level prüfen
        let categoryLevel = categoryLevels[category] ?? globalMinimumLevel
        let effectiveLevel = max(categoryLevel, globalMinimumLevel)

        return level >= effectiveLevel
    }

    /// Setzt ein Log-Level für eine spezifische Kategorie
    func setLevel(_ level: LogLevel, for category: LogCategory) {
        categoryLevels[category] = level
    }

    /// Setzt alle Einstellungen auf Standard zurück
    func resetToDefaults() {
        isLoggingEnabled = false
        globalMinimumLevel = .debug
        showPerformanceLogs = true
        showTimestamps = true
        includeSourceLocation = true

        // Alle Kategorien auf Debug setzen
        var newCategoryLevels: [LogCategory: LogLevel] = [:]
        for category in LogCategory.allCases {
            newCategoryLevels[category] = .debug
        }
        categoryLevels = newCategoryLevels
    }

    // MARK: - Persistence

    private func saveCategoryLevels() {
        let dict = categoryLevels.reduce(into: [String: Int]()) { result, entry in
            result[entry.key.rawValue] = entry.value.rawValue
        }
        UserDefaults.standard.set(dict, forKey: "logging.categoryLevels")
    }

    private static func loadCategoryLevels() -> [LogCategory: LogLevel] {
        guard let dict = UserDefaults.standard.dictionary(forKey: "logging.categoryLevels") as? [String: Int] else {
            // Defaults: Alle auf Debug
            return LogCategory.allCases.reduce(into: [:]) { result, category in
                result[category] = .debug
            }
        }

        return dict.reduce(into: [:]) { result, entry in
            if let category = LogCategory(rawValue: entry.key),
               let level = LogLevel(rawValue: entry.value) {
                result[category] = level
            }
        }
    }
}

// MARK: - LogLevel Extension für UserDefaults

extension LogLevel {
    init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .debug
        case 1: self = .info
        case 2: self = .notice
        case 3: self = .warning
        case 4: self = .error
        case 5: self = .critical
        default: return nil
        }
    }
}
