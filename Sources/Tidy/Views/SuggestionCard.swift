import SwiftUI
import TidyCore

struct SuggestionCard: View {
    let suggestion: AppState.Suggestion
    let onApprove: () -> Void
    let onReject: () -> Void
    let onRedirect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForExtension(suggestion.candidate.fileExtension))
                    .foregroundStyle(.secondary)
                Text(suggestion.candidate.filename)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                Text(shortenPath(suggestion.decision.destination))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Text("\(suggestion.decision.confidence)% confident")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onApprove) { Image(systemName: "checkmark") }
                    .buttonStyle(.plain).foregroundStyle(.green).help("Approve")
                Button(action: onReject) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.red).help("Reject")
                Button(action: onRedirect) { Image(systemName: "ellipsis") }
                    .buttonStyle(.plain).foregroundStyle(.blue).help("Choose destination")
            }
        }
        .padding(8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func iconForExtension(_ ext: String?) -> String {
        switch ext {
        case "pdf": "doc.fill"
        case "png", "jpg", "jpeg", "heic", "tiff": "photo"
        case "dmg", "pkg": "shippingbox"
        case "zip", "gz", "tar": "archivebox"
        case "docx", "doc", "txt", "md": "doc.text"
        case "csv", "xlsx": "tablecells"
        default: "doc"
        }
    }

    private func shortenPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
