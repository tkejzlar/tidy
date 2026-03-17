import SwiftUI
import TidyCore

struct PanelView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tidy").font(.headline)
                Spacer()
                Button(action: { state.showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain)
                Button(action: { state.isPaused.toggle() }) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                }.buttonStyle(.plain)
            }
            .padding()
            Divider()
            Text("Loading...").foregroundStyle(.secondary).padding()
            Spacer()
        }
        .frame(width: 360, height: 480)
    }
}
