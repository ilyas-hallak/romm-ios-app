//
//  ServerURLRebaser.swift
//  romm
//

import Foundation

/// Rewrites a request URL built against one known server address onto the currently active one.
///
/// Covers loaded before an endpoint switch still carry an absolute URL for whichever address was
/// active back then. That address can now be unreachable, so the request is rebased onto the
/// active base whenever it starts with one of the known ones. Comparison is a plain string prefix
/// after trimming a trailing slash from every base, which keeps base paths like
/// `https://host/romm` working, and the prefix must be followed by `/`, `?` or the end of the
/// string so `https://host` never matches `https://hostother...`. A foreign host, such as an
/// external cover CDN, matches none of the known bases and is returned untouched.
enum ServerURLRebaser {
    static func rebase(_ url: URL, activeBaseURL: String, knownBaseURLs: [String]) -> URL {
        let urlString = url.absoluteString
        let trimmedActive = trimmed(activeBaseURL)

        for knownBaseURL in knownBaseURLs {
            let trimmedKnown = trimmed(knownBaseURL)
            guard !trimmedKnown.isEmpty, trimmedKnown != trimmedActive else { continue }
            guard let suffix = suffix(of: urlString, afterPrefix: trimmedKnown) else { continue }
            return URL(string: trimmedActive + suffix) ?? url
        }

        return url
    }

    private static func trimmed(_ base: String) -> String {
        base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Returns what follows `prefix` in `string`, but only when `prefix` is followed by `/`, `?`
    /// or the end of the string.
    private static func suffix(of string: String, afterPrefix prefix: String) -> String? {
        guard string.hasPrefix(prefix) else { return nil }
        let rest = string.dropFirst(prefix.count)
        guard rest.isEmpty || rest.hasPrefix("/") || rest.hasPrefix("?") else { return nil }
        return String(rest)
    }
}
