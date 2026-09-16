//
//  RommSessionCookie.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

/// The `romm_session` cookie handed out by `POST /api/login`. It is the only
/// thing the server's Socket.IO endpoint accepts as authentication, and it is a
/// credential, so it is never logged and never written to disk.
struct RommSessionCookie: Sendable, Equatable {
    /// Ready to use as the value of a `Cookie` header, e.g. `romm_session=…`.
    let headerValue: String
    let expiresAt: Date?

    static let name = "romm_session"
}
