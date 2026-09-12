//
//  PScanRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

protocol PScanRepository {
    /// Starts a scan and returns the live event stream of that run. The stream
    /// finishes when the scan ends, when it is refused, or when the caller stops
    /// iterating, which also tears the socket down.
    func startScan(type: LibraryScanType, platformIds: [Int]) async throws -> AsyncStream<LibraryScanEvent>

    /// Asks the server to stop the running scan. Works whether the scan was
    /// started from this app or somewhere else.
    func stopScan() async throws

    /// Stores the credentials a scan session needs, for the case where the app
    /// signed in with a token and has no password on hand.
    func saveScanCredentials(username: String, password: String) throws
}
