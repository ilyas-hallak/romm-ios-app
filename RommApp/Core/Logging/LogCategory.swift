// SPDX-License-Identifier: MIT

import Foundation

/// Kategorien für verschiedene App-Bereiche
enum LogCategory: String, CaseIterable, Codable {
    case network = "Network"
    case ui = "UI"
    case data = "Data"
    case auth = "Auth"
    case performance = "Performance"
    case general = "General"
    case manual = "Manual"
    case viewModel = "ViewModel"

    /// Emoji-Repräsentation für bessere Lesbarkeit
    var emoji: String {
        switch self {
        case .network: return "🌐"
        case .ui: return "🎨"
        case .data: return "🗃️"
        case .auth: return "🔐"
        case .performance: return "⚡"
        case .general: return "📦"
        case .manual: return "📚"
        case .viewModel: return "🔄"
        }
    }

    /// Beschreibung der Kategorie
    var description: String {
        switch self {
        case .network: return "Netzwerk-Operationen, API-Aufrufe"
        case .ui: return "Benutzeroberfläche, View-Updates"
        case .data: return "Daten-Operationen, Repository"
        case .auth: return "Authentifizierung, Login"
        case .performance: return "Leistungs-Metriken, Timing"
        case .general: return "Allgemeine Logik, Use Cases"
        case .manual: return "PDF-Manual System"
        case .viewModel: return "View-Model Layer, State"
        }
    }
}
