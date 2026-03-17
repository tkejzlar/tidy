import SwiftUI
import TidyCore

struct RecentMoveRow: View {
    let move: MoveRecord
    let onUndo: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(move.filename)
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(shortenPath((move.destinationPath as NSString).deletingLastPathComponent))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(timeAgo(move.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !move.wasUndone {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("Undo")
            }
        }
        .padding(6)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return (path as NSString).lastPathComponent
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}
