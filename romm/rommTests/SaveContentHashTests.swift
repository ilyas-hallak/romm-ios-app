import Testing
import Foundation
@testable import romm

struct SaveContentHashTests {

    /// Locks the hash to a known MD5 value so a refactor cannot silently
    /// change what the server sees as `content_hash`.
    @Test func hashesAFixedInputToItsKnownMD5() {
        let data = "hello".data(using: .utf8)!

        #expect(SaveContentHash.of(data) == "5d41402abc4b2a76b9719d911017c592")
    }
}
