import CryptoKit
import Foundation

enum SaveContentHash {
    /// Lowercase hex MD5 over the save's bytes, the identity the server
    /// deduplicates on. Every sync path has to produce the same string here
    /// or the server stops recognising a save it already holds.
    static func of(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
