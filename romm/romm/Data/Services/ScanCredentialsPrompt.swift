//
//  ScanCredentialsPrompt.swift
//  romm
//
//  Created by Ilyas Hallak on 13.09.26.
//
//  The one seam through which the scan session reaches a human. It exists only
//  because a scan can currently be started over Socket.IO alone, and that
//  handshake authenticates with a session cookie, which the server hands out
//  for a username and password. Once the server grows a REST route for starting
//  a scan, this protocol, its presenter and the sheet behind it are deleted and
//  nothing else in the feature has to change.
//

import Foundation

struct ScanCredentials: Sendable {
    let username: String
    let password: String
}

/// Deliberately not `@MainActor`: the session provider holds it from a
/// non-isolated context and only ever awaits it, the presenter hops to the
/// main actor on its own.
protocol PScanCredentialsPrompt: AnyObject, Sendable {
    /// Asks the user for their RomM credentials. `retryReason` is set when a
    /// previous answer was refused, so the prompt can say why it is back.
    /// Returns nil when the user dismissed it.
    func credentials(retryReason: String?) async -> ScanCredentials?
}
