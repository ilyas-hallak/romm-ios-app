//
//  LicensesView.swift
//  romm
//
//  Created by Ilyas Hallak on 15.05.26.
//

import SwiftUI

struct LicensesView: View {
    var body: some View {
        List {
            #if !APP_STORE
            Section(header: Text("Emulator Engines")) {
                entry(
                    "DeltaCore & GBADeltaCore",
                    notice: "© Riley Testut. Licensed under the AGPL-3.0 license.",
                    url: "https://github.com/rileytestut/DeltaCore"
                )
            }
            #endif

            // These ship in every build, so they are listed unconditionally.
            Section(header: Text("Emulator Cores")) {
                entry(
                    "PCSX ReARMed",
                    notice: "© PCSX Team, PCSX-df Team, PCSX-Reloaded Team, Exophase and notaz. "
                        + "Licensed under the GPL-2.0 license.",
                    url: "https://github.com/libretro/pcsx_rearmed"
                )
                entry(
                    "PPSSPP",
                    notice: "© Henrik Rydgård and contributors. "
                        + "Licensed under the GPL-2.0-or-later license.",
                    url: "https://github.com/hrydgard/ppsspp"
                )
                entry(
                    "Flycast",
                    notice: "© the Flycast and reicast contributors. "
                        + "Licensed under the GPL-2.0 license.",
                    url: "https://github.com/flyinghead/flycast"
                )
                entry(
                    "Beetle PC Engine Fast",
                    notice: "© the Mednafen and libretro contributors. "
                        + "Licensed under the GPL-2.0 license.",
                    url: "https://github.com/libretro/beetle-pce-fast-libretro"
                )
                entry(
                    "Genesis Plus GX",
                    notice: "© 1998-2003 Charles MacDonald, © 2007-2026 Eke-Eke. "
                        + "Portions © Nicola Salmoria and the MAME team. "
                        + "Distributed under its own non-commercial license.",
                    url: "https://github.com/libretro/Genesis-Plus-GX"
                )
            }

            Section(header: Text("Libraries")) {
                entry(
                    "ZIPFoundation",
                    notice: "© 2017-2026 Thomas Zoechling. Licensed under the MIT license.",
                    url: "https://github.com/weichsel/ZIPFoundation"
                )
            }
        }
        .navigationTitle("Licenses")
    }

    /// One attribution block. Keeping it in one place means every entry below
    /// gets the same shape, whichever build is being compiled.
    private func entry(_ name: String, notice: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
            Text(notice)
                .font(.footnote)
            Text(url)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}
