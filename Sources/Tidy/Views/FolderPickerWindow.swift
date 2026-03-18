import SwiftUI
import AppKit

/// Opens an NSOpenPanel completely independently of the MenuBarExtra.
/// The key insight: we must close the MenuBarExtra panel FIRST, then open
/// NSOpenPanel on the next run loop tick. And we must NOT use runModal()
/// (which blocks and gets cancelled when the MenuBarExtra dismisses) or
/// beginSheetModal (which requires a parent window). Instead we use
/// begin() which runs the panel as a standalone modeless dialog.
@MainActor
enum FolderPicker {
    private static var retainedPanel: NSOpenPanel?

    static func pick(prompt: String = "Choose", message: String? = nil, completion: @escaping @MainActor (URL) -> Void) {
        // Step 1: Close the MenuBarExtra panel by ordering out all NSPanels
        for window in NSApp.windows where window is NSPanel {
            window.orderOut(nil)
        }

        // Step 2: On the next run loop tick (after MenuBarExtra is gone),
        // show NSOpenPanel as a standalone window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = prompt
            panel.level = .modalPanel
            if let message { panel.message = message }

            // Retain the panel so it doesn't get deallocated
            retainedPanel = panel

            // Activate the app so the panel appears in front
            NSApp.activate(ignoringOtherApps: true)

            // begin() runs the panel as a standalone modeless dialog
            // — not attached to any window, not blocking any thread
            panel.begin { response in
                retainedPanel = nil
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        }
    }
}
