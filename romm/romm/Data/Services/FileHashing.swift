import Foundation
import CryptoKit

/// Hashes files without loading them into memory.
///
/// A disc image can run to several hundred MB, so `Data(contentsOf:)` risks a
/// jetsam. Everything here reads in chunks and feeds the digest incrementally.
enum FileHashing {

    /// Large enough that the syscall overhead disappears, small enough to stay
    /// invisible in the memory graph.
    private static let chunkSize = 1024 * 1024

    /// Lowercase hex SHA-1, the identifier Delta uses for an imported ROM.
    static func sha1(ofFileAt url: URL) throws -> String {
        try hash(ofFileAt: url, using: Insecure.SHA1())
    }

    static func md5(ofFileAt url: URL) throws -> String {
        try hash(ofFileAt: url, using: Insecure.MD5())
    }

    static func sha256(ofFileAt url: URL) throws -> String {
        try hash(ofFileAt: url, using: SHA256())
    }

    /// The identifier Manic EMU addresses an imported ROM by: djb2 over the
    /// *hex text* of the SHA-256, not over the ROM (`FileHashUtil.truncatedHash`).
    /// The wrapping arithmetic mirrors Manic's and must not be "fixed", or the
    /// deep link stops resolving.
    static func manicGameID(ofFileAt url: URL) throws -> String {
        String(djb2(try sha256(ofFileAt: url)))
    }

    // MARK: - Private

    /// djb2 over UTF-8, in Int so the overflow matches Manic's. `magnitude`
    /// rather than `abs`, which traps on `Int.min`.
    private static func djb2(_ string: String) -> UInt {
        string.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }.magnitude
    }

    private static func hash<H: HashFunction>(ofFileAt url: URL, using function: H) throws -> String {
        var function = function
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            function.update(data: chunk)
        }

        return function.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
