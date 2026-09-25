//
// RomFileCategory.swift
//

import Foundation

public enum RomFileCategory: String, Codable, CaseIterable {
    case game = "game"
    case dlc = "dlc"
    case hack = "hack"
    case manual = "manual"
    case walkthrough = "walkthrough"
    case patch = "patch"
    case update = "update"
    case mod = "mod"
    case demo = "demo"
    case translation = "translation"
    case prototype = "prototype"
    case cheat = "cheat"
    case soundtrack = "soundtrack"
    case screenshot = "screenshot"
    /// Any value the server sends that isn't one of the known cases yet, so a
    /// future addition never fails decoding of the whole file entry.
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RomFileCategory(rawValue: raw) ?? .unknown
    }
}
