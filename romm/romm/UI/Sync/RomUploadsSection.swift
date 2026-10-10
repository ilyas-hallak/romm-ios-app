//
//  RomUploadsSection.swift
//  romm
//
//  Shows the chunked ROM upload queue on the Sync screen. Reads
//  `RomUploadQueueManager.shared` directly, the same way the Downloads tab
//  reads `DownloadQueueManager.shared`, rather than threading it through
//  `SyncOverviewViewModel`.
//

import SwiftUI

struct RomUploadsSection: View {
    private let queueManager = RomUploadQueueManager.shared

    var body: some View {
        if !queueManager.jobs.isEmpty {
            Section {
                ForEach(queueManager.jobs) { job in
                    row(for: job)
                }
            } header: {
                Text("Uploads")
            } footer: {
                if queueManager.jobs.contains(where: { if case .completed = $0.state { return true } else { return false } }) {
                    Button("Clear Finished") { queueManager.clearFinished() }
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for job: RomUploadJob) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.fileName)
                Text(job.platformName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            detail(for: job)
        }
        .swipeActions {
            switch job.state {
            case .failed:
                Button("Retry") { queueManager.retry(id: job.id) }
                    .tint(.blue)
                Button("Remove", role: .destructive) { queueManager.remove(id: job.id) }
            case .queued, .uploading, .finishing:
                Button("Cancel", role: .destructive) { queueManager.cancel(id: job.id) }
            case .completed, .cancelled:
                Button("Remove", role: .destructive) { queueManager.remove(id: job.id) }
            }
        }
    }

    @ViewBuilder
    private func detail(for job: RomUploadJob) -> some View {
        switch job.state {
        case .queued:
            Text("Queued")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .uploading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .finishing:
            Text("Finishing…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.trailing)
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
