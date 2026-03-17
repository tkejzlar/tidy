import SwiftUI
import TidyCore
struct RecentMoveRow: View {
    let move: MoveRecord
    let onUndo: () -> Void
    var body: some View { Text(move.filename).font(.caption) }
}
