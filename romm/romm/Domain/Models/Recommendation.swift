//
//  Recommendation.swift
//  romm
//

import Foundation

struct Recommendation: Identifiable, Equatable {
    let rom: Rom
    let seedRomName: String?

    var id: Int { rom.id }
}
