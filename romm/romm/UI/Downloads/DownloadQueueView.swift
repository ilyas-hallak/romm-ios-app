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
                            Section {
                                ForEach(activeTasks) { task in
                                    row(for: task)
                                }
                            } header: {
                                Text("In Progress")
                            } footer: {
                                // Promises only what the background session can
                                // keep: iOS drops its transfers when the user
                                // force quits, so that is spelled out.
                                Text("Downloads keep going while the app is in the background or closed, but stop if you force quit it from the app switcher.")
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
        case .downloading(let progress, let bytesPerSecond):
            VStack(alignment: .leading, spacing: 3) {
                if let progress {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                        .animation(.easeOut(duration: 0.4), value: progress)
                } else {
                    ProgressView()
                        .tint(.accentColor)
                }
                Text(DownloadTask.progressLabel(progress: progress, bytesPerSecond: bytesPerSecond))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.4), value: progress)
            }
        case .finalizing:
            Text("Finishing up…")
                .font(.caption)
                .foregroundColor(.secondary)
        case .finished:
            Text("Downloaded")
                .font(.caption)
                .foregroundColor(.green)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func trailing(for task: DownloadTask) -> some View {
        switch task.status {
        case .queued, .downloading:
            // The row the user is looking at is also where the download is
            // stopped, so the trailing spot carries the way out instead of
            // repeating a status the line underneath the name already gives.
            Button {
                queue.cancel(id: task.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    // Grows the hit area towards the name, so the icon keeps
                    // sitting exactly where the status icons of other rows do.
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel Download")
        case .finalizing:
            // Every file is on disk and is being filed away in one go, so there
            // is no transfer left to stop, only a move to interrupt halfway.
            ProgressView()
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundColor(.secondary)
        case .failed:
            Button {
                queue.retry(id: task.id)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry Download")
        }
    }

    /// Whether the row is busy transferring or filing the ROM away, which is
    /// when it must not be swiped out of the list.
    private func isDownloading(_ task: DownloadTask) -> Bool {
        switch task.status {
        case .downloading, .finalizing: return true
        case .queued, .finished, .failed, .cancelled: return false
        }
    }
}
