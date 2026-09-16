//
//  ScanMetadataSourcesMapper.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

/// What the `scan` event has to say about metadata sources.
struct ScanMetadataSources: Equatable {
    /// The `apis` list. An empty list does not mean "server defaults", it means
    /// the server uses no metadata source at all, so a scan would only
    /// reconcile files and an `update` or `unmatched` scan would do nothing.
    let apis: [String]
    /// Playmatch is not an `apis` entry, it rides on its own flag and the
    /// server only honours it together with IGDB.
    let playmatchEnabled: Bool
}

/// Turns the heartbeat's per-source flags into the payload the scan socket
/// expects. The app does not let the user pick sources, so it sends every
/// source the server has configured, which is what the web UI does by default.
struct ScanMetadataSourcesMapper {
    /// Flag on the heartbeat paired with the string the scan payload uses. The
    /// two names differ often enough (`STEAMGRIDDB` against `sgdb`) that a
    /// derived mapping would be wrong.
    private static let sources: [(enabled: KeyPath<MetadataSourcesDict, Bool>, api: String)] = [
        (\.IGDB_API_ENABLED, "igdb"),
        (\.MOBY_API_ENABLED, "moby"),
        (\.SS_API_ENABLED, "ss"),
        (\.STEAMGRIDDB_API_ENABLED, "sgdb"),
        (\.RA_API_ENABLED, "ra"),
        (\.LAUNCHBOX_API_ENABLED, "launchbox"),
        (\.HASHEOUS_API_ENABLED, "hasheous"),
        (\.TGDB_API_ENABLED, "tgdb"),
        (\.FLASHPOINT_API_ENABLED, "flashpoint"),
        (\.HLTB_API_ENABLED, "hltb"),
        (\.LIBRETRO_API_ENABLED, "libretro"),
        (\.DEMOZOO_API_ENABLED, "demozoo"),
        (\.POUET_API_ENABLED, "pouet"),
        (\.CSDB_API_ENABLED, "csdb"),
        (\.STEAM_API_ENABLED, "steam")
    ]

    static func mapFromAPI(_ metadataSources: MetadataSourcesDict) -> ScanMetadataSources {
        let apis = sources
            .filter { metadataSources[keyPath: $0.enabled] }
            .map(\.api)

        return ScanMetadataSources(
            apis: apis,
            playmatchEnabled: metadataSources.PLAYMATCH_API_ENABLED && apis.contains("igdb")
        )
    }
}
