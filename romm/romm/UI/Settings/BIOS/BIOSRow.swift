import SwiftUI

struct BIOSRow: View {
    let status: BIOSFileStatus
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.requirement.fileName)
                        .font(.system(.body, design: .monospaced))
                    if let note = status.requirement.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !status.existsLocally && status.canDownload {
                    Button("Download", action: onDownload)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            detailLine
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusIcon: some View {
        switch (status.existsLocally, status.localHashLooksValid, status.canDownload) {
        case (true, true, _):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case (true, false, _):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case (false, _, true):
            Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case (false, _, false):
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var detailLine: some View {
        switch status.local {
        case .missing:
            switch status.server {
            case .available(_, let size, _, _):
                Text("Missing locally · Server: \(formatBytes(size))").font(.caption2).foregroundStyle(.secondary)
            case .missing:
                Text("Missing locally · Server does not have this file.").font(.caption2).foregroundStyle(.secondary)
            case .unknown:
                Text("Missing locally · Platform not found on the ROMM server.").font(.caption2).foregroundStyle(.secondary)
            }
        case .present(let md5, let size):
            HStack(spacing: 8) {
                Text("Local \(formatBytes(size))")
                Text("MD5 \(md5.prefix(8))…")
                if status.localHashLooksValid {
                    Text("verified").foregroundStyle(.green)
                } else {
                    Text("Hash unverified").foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}
