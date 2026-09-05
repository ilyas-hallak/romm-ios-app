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

    /// The identifier Manic EMU addresses an imported ROM by.
    ///
    /// Manic wants something shorter than a digest, so it hex-encodes the SHA-256
    /// and then runs djb2 over that *text* rather than over the ROM
    /// (`FileHashUtil.truncatedHash`). Reproducing it exactly is what makes
    /// `manicemu://game/<id>` land on the game Manic imported, so the wrapping
    /// arithmetic below mirrors Manic's `<<` and `&+` and must not be "fixed".
    static func manicGameID(ofFileAt url: URL) throws -> String {
        String(djb2(try sha256(ofFileAt: url)))
    }

    // MARK: - Private

    /// djb2 over UTF-8, in Int so the overflow matches Manic's.
    ///
    /// `magnitude` rather than `abs`, which traps on `Int.min`. That costs
    /// nothing: the two agree everywhere else, and on the one value where they
    /// differ Manic itself crashes, so there is no identifier to agree with.
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
