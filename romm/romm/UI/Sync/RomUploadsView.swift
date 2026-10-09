//
//  RomUploadsView.swift
//  romm
//
//  Where "Uploads" in the account menu leads on the App Store build, since
//  Save Sync (and the uploads section that normally lives inside it) is
//  hidden there. Reuses `RomUploadsSection` rather than a second upload UI.
//

import SwiftUI

struct RomUploadsView: View {
    private let queueManager = RomUploadQueueManager.shared

    var body: some View {
        List {
            RomUploadsSection()
        }
        .overlay {
            if queueManager.jobs.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Uploads"),
                    systemImage: "arrow.up.circle"
                )
            }
        }
        .navigationTitle(String(localized: "Uploads"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RomUploadsView()
    }
}
