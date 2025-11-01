// SPDX-License-Identifier: MIT

import Foundation

/*
 LOGGING SYSTEM - VERWENDUNGSBEISPIELE

 Das erweiterte Logging-System für RomM iOS App bietet:

 ✅ Enable/Disable Toggle - Logging ist standardmäßig deaktiviert
 ✅ Picker für Log-Levels - Statt Segmented Control
 ✅ Detail-Screens für jede Kategorie
 ✅ In-App Log-Viewer mit Suchfunktion
 ✅ Filter nach Level und Kategorie
 ✅ Export-Funktionen (Text, JSON)

 WICHTIG: Logging ist standardmäßig DEAKTIVIERT und sammelt keine Logs,
 bis es vom Benutzer manuell aktiviert wird!
*/

// MARK: - Beispiel 1: Einfaches Logging in ViewModels

class ExampleViewModel {
    private let logger = Logger.viewModel

    func loadData() {
        logger.info("Starting data load")

        // Simulation einer Operation
        do {
            // ...
            logger.debug("Data processed successfully")
        } catch {
            logger.error("Failed to load data: \(error)")
        }
    }
}

// MARK: - Beispiel 2: Netzwerk-Logging

class ExampleNetworkService {
    private let logger = Logger.network

    func fetchRoms() async throws {
        let url = "https://api.example.com/roms"

        logger.info("Fetching ROMs from API")

        // Convenience-Methode für Netzwerk-Requests
        logger.logNetworkRequest(method: "GET", url: url)

        do {
            // ... Network call
            logger.logNetworkRequest(method: "GET", url: url, statusCode: 200)
        } catch {
            logger.logNetworkError(method: "GET", url: url, error: error)
            throw error
        }
    }
}

// MARK: - Beispiel 3: Performance-Messungen

class ExampleService {
    private let logger = Logger.performance

    func heavyOperation() {
        // Automatische Performance-Messung
        let measurement = PerformanceMeasurement(operation: "Heavy Operation")

        // ... Schwere Berechnung
        Thread.sleep(forTimeInterval: 0.5)

        measurement.end() // Loggt: "Heavy Operation took 0.500s"
    }

    func anotherOperation() {
        let start = CFAbsoluteTimeGetCurrent()

        // ... Operation

        let duration = CFAbsoluteTimeGetCurrent() - start
        logger.logPerformance("Another Operation", duration: duration)
    }
}

// MARK: - Beispiel 4: Verschiedene Log-Levels

class ExampleAuthService {
    private let logger = Logger.auth

    func login(username: String, password: String) async throws {
        logger.debug("Login attempt for user: \(username)")

        guard !username.isEmpty else {
            logger.warning("Login attempt with empty username")
            throw AuthError.invalidCredentials
        }

        do {
            // ... Auth logic
            logger.info("User \(username) logged in successfully")
        } catch {
            logger.error("Login failed for user \(username): \(error)")
            throw error
        }
    }

    func criticalSecurityEvent() {
        logger.critical("Security breach detected!")
    }
}

enum AuthError: Error {
    case invalidCredentials
}

// MARK: - Beispiel 5: UI-Logging

class ExampleUILogger {
    private let logger = Logger.ui

    func viewDidAppear() {
        logger.debug("RomDetailView appeared")
    }

    func userTappedButton() {
        logger.info("User tapped 'Download Manual' button")
    }

    func viewRenderingIssue() {
        logger.warning("View rendering took longer than expected")
    }
}

// MARK: - Beispiel 6: Data/Repository Logging

class ExampleRepository {
    private let logger = Logger.data

    func saveToCache(rom: String) {
        logger.debug("Saving ROM to cache: \(rom)")

        // ... Cache logic

        logger.info("ROM cached successfully: \(rom)")
    }

    func databaseQuery() {
        logger.debug("Executing database query")

        let measurement = PerformanceMeasurement(
            operation: "Database Query",
            logger: logger
        )

        // ... Query

        measurement.end()
    }
}

// MARK: - Beispiel 7: Konfiguration zur Laufzeit

class LoggingConfigurationExample {
    func setupLoggingForDevelopment() {
        let config = LogConfiguration.shared

        // Logging aktivieren
        config.isLoggingEnabled = true

        // Alles auf Debug für Entwicklung
        config.globalMinimumLevel = .debug
        config.showPerformanceLogs = true
        config.showTimestamps = true
        config.includeSourceLocation = true
    }

    func setupLoggingForProduction() {
        let config = LogConfiguration.shared

        // Nur wichtige Logs in Produktion
        config.isLoggingEnabled = true
        config.globalMinimumLevel = .warning
        config.showPerformanceLogs = false
        config.includeSourceLocation = false
    }

    func debugNetworkIssues() {
        let config = LogConfiguration.shared

        // Nur Netzwerk debuggen
        config.isLoggingEnabled = true
        config.setLevel(.debug, for: .network)
        config.setLevel(.debug, for: .auth)
        config.setLevel(.error, for: .ui)
        config.setLevel(.error, for: .data)
    }
}

// MARK: - Beispiel 8: Logs programmatisch filtern

class LogAnalysisExample {
    func findErrors() {
        let store = LogStore.shared

        // Nur Error und Critical Logs
        let errors = store.filter(levels: [.error, .critical])

        print("Found \(errors.count) errors")
    }

    func findNetworkIssues() {
        let store = LogStore.shared

        // Nur Network-Kategorie
        let networkLogs = store.filter(categories: [.network])

        print("Found \(networkLogs.count) network logs")
    }

    func searchLogs() {
        let store = LogStore.shared

        // Suche nach Text
        let searchResults = store.filter(searchText: "ROM")

        print("Found \(searchResults.count) logs containing 'ROM'")
    }

    func exportLogs() {
        let store = LogStore.shared

        // Als Text
        let textExport = store.exportAsText()
        print(textExport)

        // Als JSON
        if let jsonData = store.exportAsJSON() {
            // Speichern oder teilen
            print("JSON export size: \(jsonData.count) bytes")
        }
    }
}

/*
 INTEGRATION IN SETTINGS

 Um die Logging-Einstellungen in den App-Settings anzuzeigen:

 ```swift
 NavigationLink("Logging-Konfiguration") {
     LogSettingsView()
 }
 ```

 FEATURES:

 1. Master Toggle
    - Logging komplett ein/ausschalten
    - Default: AUS (keine Logs werden gesammelt)

 2. Globales Log-Level
    - Picker statt Segmented Control
    - Detail-Screen mit Beschreibungen
    - Hierarchie: Debug < Info < Notice < Warning < Error < Critical

 3. Kategorie-spezifische Settings
    - Jede Kategorie hat einen Detail-Screen
    - Individuelles Log-Level pro Kategorie
    - Beschreibung was jede Kategorie loggt

 4. Display-Optionen
    - Performance-Logs ein/aus
    - Zeitstempel ein/aus
    - Source-Location (Datei:Zeile) ein/aus

 5. Log-Viewer
    - Suchfunktion (durchsucht Message, Datei, Funktion)
    - Filter nach Log-Level (mehrfach auswählbar)
    - Filter nach Kategorie (mehrfach auswählbar)
    - Expandable Details pro Log-Eintrag
    - Live-Updates wenn neue Logs kommen
    - Export als Text oder JSON
    - Alle Logs löschen

 6. Reset-Funktion
    - Alle Einstellungen auf Standard zurücksetzen
    - Default: Logging AUS, alle Level auf Debug

 PERFORMANCE:

 - Wenn Logging deaktiviert ist: KEIN Performance-Overhead
 - Logs werden nur verarbeitet wenn sie den Level erreichen
 - Maximale Log-Anzahl: 10.000 (älteste werden automatisch entfernt)
 - Thread-sichere Log-Speicherung
 - Lazy evaluation von String-Interpolation

 BEST PRACTICES:

 1. Logging für Release standardmäßig deaktiviert lassen
 2. Debug-Level für lokale Entwicklung
 3. Warning/Error für Produktion
 4. Sensitive Daten nie loggen (Passwörter, Tokens, etc.)
 5. Performance-Messungen nur wenn nötig
 6. Kategorie-spezifische Level für gezieltes Debugging
*/
