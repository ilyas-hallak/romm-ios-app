import Foundation

protocol PHelpRepository {
    /// The help document as Markdown. Never throws: help that fails to load is
    /// worse than help that is slightly out of date, so the bundled copy is
    /// always there as a fallback.
    func helpMarkdown() async -> String
}
