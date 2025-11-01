// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Log-Level definieren die Wichtigkeit von Log-Nachrichten
enum LogLevel: String, CaseIterable, Codable, Comparable {
    case debug = "Debug"
    case info = "Info"
    case notice = "Notice"
    case warning = "Warning"
    case error = "Error"
    case critical = "Critical"

    /// Emoji-Repräsentation für bessere Lesbarkeit
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

    /// OSLogType für Apple's Unified Logging System
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .error
        case .error: return .error
        case .critical: return .fault
        }
    }

    /// Numerischer Wert für Vergleiche
    var rawValue: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .warning: return 3
        case .error: return 4
        case .critical: return 5
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
