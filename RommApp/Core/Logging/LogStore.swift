// SPDX-License-Identifier: MIT

import Foundation
import Combine

/// Zentrale Speicherung aller Log-Einträge im Speicher
class LogStore: ObservableObject {
    static let shared = LogStore()

    /// Maximale Anzahl an Logs die gespeichert werden
    private let maxLogCount = 10000

    /// Alle gespeicherten Log-Einträge
    @Published private(set) var entries: [LogEntry] = []

    /// Thread-sichere Queue für Log-Operationen
    private let queue = DispatchQueue(label: "com.romm.app.logstore", qos: .utility)

    private init() {}

    /// Fügt einen neuen Log-Eintrag hinzu
    func add(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.entries.append(entry)

                // Alte Einträge entfernen wenn Limit erreicht
                if self.entries.count > self.maxLogCount {
                    let removeCount = self.entries.count - self.maxLogCount
                    self.entries.removeFirst(removeCount)
                }
            }
        }
    }

    /// Löscht alle Log-Einträge
    func clear() {
        queue.async { [weak self] in
            DispatchQueue.main.async {
                self?.entries.removeAll()
            }
        }
    }

    /// Filtert Log-Einträge nach verschiedenen Kriterien
    func filter(
        searchText: String = "",
        levels: Set<LogLevel>? = nil,
        categories: Set<LogCategory>? = nil
    ) -> [LogEntry] {
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
        if let levels = levels, !levels.isEmpty {
            filtered = filtered.filter { levels.contains($0.level) }
        }

        // Nach Kategorien filtern
        if let categories = categories, !categories.isEmpty {
            filtered = filtered.filter { categories.contains($0.category) }
        }

        return filtered
    }

    /// Exportiert Logs als Text
    func exportAsText() -> String {
        entries.map { $0.formattedString }.joined(separator: "\n")
    }

    /// Exportiert Logs als JSON
    func exportAsJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(entries)
    }
}
