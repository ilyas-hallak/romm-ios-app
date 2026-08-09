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
            Section(header: Text("Emulator Engines")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DeltaCore & GBADeltaCore")
                        .font(.headline)
                    Text("© Riley Testut. Licensed under the AGPL-3.0 license.")
                        .font(.footnote)
                    Text("https://github.com/rileytestut/DeltaCore")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Licenses")
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}
