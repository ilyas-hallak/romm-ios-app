//
//  CoverURLResolver.swift
//  romm
//

import Foundation

/// Turns the cover paths RomM reports (`path_cover_small`, `path_cover_large`) into absolute URLs
/// on the user's own server.
///
/// Those paths are relative to the server root and carry a cache-busting timestamp that contains a
/// space, for example `assets/romm/resources/roms/6/123/cover/small.png?ts=2026-07-15 22:14:51`.
/// `URL(string:)` rejects such a string, so the path and the query part are percent encoded
/// separately before they are joined again.
struct CoverURLResolver {
    /// Server URL without a trailing slash, `nil` when the app is not set up yet.
    private let baseURL: String?

    init(serverURL: String?) {
        let trimmed = serverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.baseURL = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Resolves a single cover path against the server URL.
    ///
    /// Returns `nil` for a missing or empty path, and also for a relative path while no server URL
    /// is configured, because such a path cannot be loaded on its own. A value that is already
    /// absolute is kept as it is, only its encoding gets repaired.
    func absoluteURLString(for path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }

        if path.hasPrefix("http") {
            return Self.percentEncoded(path)
        }

        guard let baseURL else { return nil }
        let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return nil }

        return Self.percentEncoded("\(baseURL)/\(relativePath)")
    }

    /// Characters that stay as they are in the path part. `%` is treated as safe so a value that
    /// already carries an escape is not encoded a second time into `%2520`.
    private static let allowedInPath = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%"))

    /// Same idea for the query part, see `allowedInPath`.
    private static let allowedInQuery = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "%"))

    /// Percent encodes an URL string that the server sent unencoded.
    ///
    /// Path and query have to be handled separately, `.urlPathAllowed` would keep a `?` literal and
    /// `.urlQueryAllowed` would keep a `/` literal, so neither set fits the whole string.
    private static func percentEncoded(_ urlString: String) -> String? {
        let parts = urlString.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let encodedPath = String(parts[0]).addingPercentEncoding(withAllowedCharacters: allowedInPath) else {
            return nil
        }
        guard parts.count > 1 else { return encodedPath }
        guard let encodedQuery = String(parts[1]).addingPercentEncoding(withAllowedCharacters: allowedInQuery) else {
            return encodedPath
        }

        return "\(encodedPath)?\(encodedQuery)"
    }
}
