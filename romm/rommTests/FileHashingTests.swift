import Testing
import Foundation
import CryptoKit
@testable import romm

struct FileHashingTests {

    private func makeFile(_ data: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileHashingTests-\(UUID().uuidString)")
        try data.write(to: url)
        return url
    }

    /// Known vectors, so a change to the chunking cannot quietly alter the output.
    @Test func hashesTheEmptyFile() throws {
        let url = try makeFile(Data())
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try FileHashing.sha1(ofFileAt: url) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect(try FileHashing.md5(ofFileAt: url) == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test func hashesAKnownString() throws {
        let url = try makeFile(Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try FileHashing.sha1(ofFileAt: url) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(try FileHashing.md5(ofFileAt: url) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(try FileHashing.sha256(ofFileAt: url)
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    /// The chunk loop only proves itself on a file that does not fit in one read.
    /// ROMs are always in this range, the small cases above are not representative.
    @Test func hashesAFileLargerThanOneChunk() throws {
        let data = Data(repeating: 0x41, count: 3 * 1024 * 1024 + 7)
        let url = try makeFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        // Same bytes hashed in one go, which is what the chunked read has to match.
        #expect(try FileHashing.sha1(ofFileAt: url) == Insecure.SHA1.hash(data: data)
            .map { String(format: "%02x", $0) }.joined())
    }

    @Test func reportsAMissingFile() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try FileHashing.sha1(ofFileAt: missing) }
    }
}
