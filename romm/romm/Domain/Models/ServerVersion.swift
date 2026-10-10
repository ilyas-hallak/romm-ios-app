//
//  ServerVersion.swift
//  romm
//

import Foundation

/// Minimal semantic-version compare shared by every repository that gates a
/// feature on the connected server's version.
enum ServerVersion {
    /// -1, 0 or 1, the way `Comparable` expects. `"development"` builds
    /// compare above every release version, a pre-release suffix after `"-"`
    /// is ignored, and a missing component counts as 0.
    static func compare(_ a: String, _ b: String) -> Int {
        if a == "development" { return 1 }
        if b == "development" { return -1 }
        let baseA = a.split(separator: "-").first.map(String.init) ?? a
        let baseB = b.split(separator: "-").first.map(String.init) ?? b
        let pa = baseA.split(separator: ".").compactMap { Int($0) }
        let pb = baseB.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return -1 }
            if x > y { return 1 }
        }
        return 0
    }
}
