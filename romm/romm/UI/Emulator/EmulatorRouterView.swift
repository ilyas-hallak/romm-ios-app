//
//  EmulatorRouterView.swift
//  romm
//
//  Created by Ilyas Hallak on 15.05.26.
//

import SwiftUI

struct EmulatorRouterView: View {
    let decision: LaunchDecision
    /// Save-state slot to auto-load once the core is running, chosen in the
    /// pre-launch sheet. `nil` starts a fresh session. The web emulator has no
    /// save-state support, so it ignores this.
    var resumeSlot: Int? = nil

    var body: some View {
        switch decision {
        case .web(let rom):
            EmulatorView(rom: rom)
        case .native(let rom, let gameType):
            NativeEmulatorView(rom: rom, gameType: gameType, resumeSlot: resumeSlot)
        case .libretro(let rom, let core):
            LibretroEmulatorView(rom: rom, core: core, resumeSlot: resumeSlot)
        }
    }
}
