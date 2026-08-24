import Foundation

/// Status einer BIOS-Datei aus Sicht von App + Server.
struct BIOSFileStatus: Identifiable, Hashable {
    enum LocalState: Hashable {
        case missing
        case present(md5: String, sizeBytes: Int)
    }

    enum ServerState: Hashable {
        case unknown
        case missing
        case available(firmwareId: Int, sizeBytes: Int, md5: String, isVerified: Bool)
    }

    let requirement: LibretroBIOSFile
    let local: LocalState
    let server: ServerState

    var id: String { requirement.fileName }

    var existsLocally: Bool {
        if case .present = local { return true }
        return false
    }

    var canDownload: Bool {
        if case .available = server { return true }
        return false
    }

    /// Lokaler Hash matcht entweder kanonisch (offline) oder Server-Hash.
    var localHashLooksValid: Bool {
        guard case .present(let localMD5, _) = local else { return false }
        if let canonical = requirement.canonicalMD5?.lowercased(),
           !canonical.isEmpty,
           localMD5.lowercased() == canonical {
            return true
        }
        if case .available(_, _, let serverMD5, _) = server,
           !serverMD5.isEmpty,
           serverMD5.lowercased() == localMD5.lowercased() {
            return true
        }
        return false
    }
}

enum BIOSFileHashing {
    static func md5(of url: URL) -> String? {
        try? FileHashing.md5(ofFileAt: url)
    }

    static func fileSize(of url: URL) -> Int? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.intValue
    }
}
