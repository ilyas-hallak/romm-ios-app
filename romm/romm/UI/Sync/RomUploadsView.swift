//
//  RomUploadsView.swift
//  romm
//
//  Where "Uploads" in the account menu leads, the one place the upload
//  queue is shown.
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
