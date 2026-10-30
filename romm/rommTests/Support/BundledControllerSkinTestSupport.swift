#if !APP_STORE
import Foundation

nonisolated enum BundledControllerSkinTestSupport {
    private static let maximumPointerSize = 1024

    static func shouldRunRealAssetTests(for urls: [URL?]) -> Bool {
        !urls.contains { isUnresolvedLFSPointer(at: $0) }
    }

    static func isUnresolvedLFSPointer(at url: URL?) -> Bool {
        guard let url, let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: maximumPointerSize + 1) else { return false }
        return isUnresolvedLFSPointer(data: header)
    }

    static func isUnresolvedLFSPointer(data: Data) -> Bool {
        guard data.count <= maximumPointerSize,
              let text = String(data: data, encoding: .utf8) else { return false }
        var lines = text.components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }
        if lines.last == "" { lines.removeLast() }
        guard lines.count == 3,
              lines[0] == "version https://git-lfs.github.com/spec/v1",
              lines[1].hasPrefix("oid sha256:"),
              lines[2].hasPrefix("size ") else { return false }

        let objectID = lines[1].dropFirst("oid sha256:".count)
        let size = lines[2].dropFirst("size ".count)
        return objectID.utf8.count == 64
            && objectID.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && !size.isEmpty
            && size.utf8.allSatisfy { (48...57).contains($0) }
            && UInt64(size) != nil
    }
}
#endif
