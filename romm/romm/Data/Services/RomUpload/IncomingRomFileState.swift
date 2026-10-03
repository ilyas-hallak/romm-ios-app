//
//  IncomingRomFileState.swift
//  romm
//
//  Holds the file most recently opened into the app, so `AppView` can present
//  `RomUploadSheet` from a single piece of state regardless of whether the
//  open came in before or after the root view appeared.
//

import Foundation
import Observation

@Observable
@MainActor
final class IncomingRomFileState {
    static let shared = IncomingRomFileState()

    var pendingFile: StagedRomFile?

    private init() {}
}
