//
//  PRomUploadSignInHintStore.swift
//  romm
//

import Foundation

/// Whether the one-time "sign in again to upload" hint on Home has already
/// been shown on this installation.
protocol PRomUploadSignInHintStore: AnyObject {
    var hasShownMissingScopeHint: Bool { get }
    func markMissingScopeHintShown()
}
