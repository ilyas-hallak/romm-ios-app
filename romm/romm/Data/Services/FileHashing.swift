import Foundation
import CryptoKit

/// Hashes files without loading them into memory.
///
/// ROMs run from a few hundred KB up to disc images of several hundred MB, and
/// `Data(contentsOf:)` on one of those is a reliable way to get the app jetsammed.
/// Everything here reads in chunks and feeds the digest incrementally.
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

    // MARK: - Private

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
