// SPDX-License-Identifier: MIT

import Foundation

/// Repräsentiert einen einzelnen Log-Eintrag
struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String
    let function: String
    let line: Int

    init(
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.line = line
    }

    /// Formatierte Darstellung des Log-Eintrags
    var formattedString: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = timeFormatter.string(from: timestamp)

        return "[\(timeString)] \(level.emoji) [\(category.rawValue)] [\(file):\(line)] \(function) - \(message)"
    }

    /// Kompakte Darstellung ohne Source-Location
    var compactString: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: timestamp)

        return "[\(timeString)] \(level.emoji) \(category.emoji) \(message)"
    }
}
