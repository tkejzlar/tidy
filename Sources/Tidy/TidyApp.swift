import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PanelView(state: appState)
                .task {
                    appState.requestNotificationPermission()
                    await appState.start()
                }
        } label: {
            Image(systemName: appState.iconName)
        }
        .menuBarExtraStyle(.window)
    }
}
