//
//  EmulatorMenuButtonOverlay.swift
//  romm
//
//  Created by Ilyas Hallak on 10.09.26.
//

import SwiftUI

/// Standalone menu button shown in the top-trailing corner when the on-screen
/// touch controls are hidden (physical controller / Controller Mode "On"), so
/// the player can still reach the pause/save/quit menu.
struct EmulatorMenuButtonOverlay: View {
    let action: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: action) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .accessibilityLabel("Menu")
                .padding(.top, 6)
                .padding(.trailing, 12)
            }
            Spacer()
        }
    }
}
