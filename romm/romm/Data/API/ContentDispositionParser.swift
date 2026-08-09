import Foundation

/// Parses a filename out of a `Content-Disposition` header value.
enum ContentDispositionParser {

    /// Returns the filename from a `Content-Disposition` value, handling both the
    /// RFC 5987 `filename*=` form (optionally with a `charset'lang''` prefix) and the
    /// plain `filename=` form, with or without surrounding quotes.
    static func filename(from value: String?) -> String? {
        guard let value else { return nil }

        let parameters = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }

        // RFC 5987 extended form takes precedence: filename*=UTF-8''name.zip
        if let param = parameters.first(where: { $0.lowercased().hasPrefix("filename*=") }) {
            var raw = String(param.dropFirst("filename*=".count))
            if let lastQuote = raw.range(of: "''", options: .backwards) {
                raw = String(raw[lastQuote.upperBound...])
            }
            let decoded = raw.removingPercentEncoding ?? raw
            let unquoted = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !unquoted.isEmpty { return unquoted }
        }

        if let param = parameters.first(where: { $0.lowercased().hasPrefix("filename=") }) {
            let raw = String(param.dropFirst("filename=".count))
            let unquoted = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !unquoted.isEmpty { return unquoted }
        }

        return nil
    }
}
