import SwiftUI

/// Shows the current download queue: active (queued / downloading) items and
/// completed (finished / failed) ones. Presented as a sheet from the Downloads tab.
struct DownloadQueueView: View {
    private let queue = DownloadQueueManager.shared
    @Environment(\.dismiss) private var dismiss

    private var activeTasks: [DownloadTask] { queue.tasks.filter { $0.isActive } }
    private var completedTasks: [DownloadTask] { queue.tasks.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            Group {
                if queue.tasks.isEmpty {
                    emptyState
                } else {
                    List {
                        if !activeTasks.isEmpty {
                            Section("In Progress") {
                                ForEach(activeTasks) { task in
                                    row(for: task)
                                }
                            }
                        }
                        if !completedTasks.isEmpty {
                            Section("Completed") {
                                ForEach(completedTasks) { task in
                                    row(for: task)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !completedTasks.isEmpty {
                        Button("Clear") { queue.clearCompleted() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("No Downloads")
                .font(.title3).fontWeight(.semibold)
            Text("ROMs you download will appear here while they transfer.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private func row(for task: DownloadTask) -> some View {
        HStack(spacing: 12) {
            if let slug = task.platformSlug {
                Image(slug)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "gamecontroller")
                    .frame(width: 40, height: 40)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                statusLine(for: task)
            }

            Spacer()

            trailing(for: task)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isDownloading(task) {
                Button(role: .destructive) {
                    queue.remove(id: task.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func statusLine(for task: DownloadTask) -> some View {
        switch task.status {
        case .queued:
            Text("Queued")
                .font(.caption)
                .foregroundColor(.secondary)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 3) {
                if let progress {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .tint(.accentColor)
                    Text("Downloading…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        case .finished:
            Text("Downloaded")
                .font(.caption)
                .foregroundColor(.green)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func trailing(for task: DownloadTask) -> some View {
        switch task.status {
        case .queued:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .downloading:
            ProgressView()
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Button {
                queue.retry(id: task.id)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func isDownloading(_ task: DownloadTask) -> Bool {
        if case .downloading = task.status { return true }
        return false
    }
}
