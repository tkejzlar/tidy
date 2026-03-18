import SwiftUI
import AppKit

/// Opens an NSOpenPanel from outside the MenuBarExtra context.
/// Spawns a temporary invisible NSWindow so the file dialog gets proper focus.
@MainActor
enum FolderPicker {
    static func pick(prompt: String = "Choose", message: String? = nil, completion: @escaping @MainActor (URL) -> Void) {
        // Create a tiny invisible anchor window
        let anchor = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        anchor.isReleasedWhenClosed = false
        anchor.alphaValue = 0
        anchor.orderFront(nil)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        if let message { panel.message = message }

        panel.beginSheetModal(for: anchor) { response in
            anchor.close()
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}
