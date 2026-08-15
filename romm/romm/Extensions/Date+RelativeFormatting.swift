import Foundation

extension Date {
    /// Returns a short relative string (e.g. "2 min. ago") using
    /// `RelativeDateTimeFormatter` with abbreviated units style.
    func relativeAbbreviated() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
