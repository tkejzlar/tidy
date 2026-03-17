import SwiftUI

struct StatusFooter: View {
    let watchPath: String
    let unsortedCount: Int
    let movedTodayCount: Int

    var body: some View {
        VStack(spacing: 2) {
            Divider()
            HStack {
                Text("\(watchPath) — \(unsortedCount) files unsorted")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("\(movedTodayCount) moved today")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
