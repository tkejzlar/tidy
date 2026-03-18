import SwiftUI
import AppKit

@MainActor
enum FolderPicker {
    static func pick(prompt: String = "Choose", message: String? = nil, completion: @escaping @MainActor (URL) -> Void) {
        // Run NSOpenPanel in a completely separate modal session
        // by using a helper NSApplication modal session approach.

        // First: close MenuBarExtra
        for window in NSApp.windows where window is NSPanel {
            window.orderOut(nil)
        }

        // Use a separate process to pick a folder via osascript
        // This completely avoids the MenuBarExtra focus issue
        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            set chosenFolder to choose folder with prompt "\(message ?? "Choose a folder")"
            return POSIX path of chosenFolder
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else { return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !path.isEmpty else { return }

                let url = URL(fileURLWithPath: path)
                DispatchQueue.main.async {
                    completion(url)
                }
            } catch {
                // silently fail
            }
        }
    }

    static func pickFile(prompt: String = "Choose", completion: @escaping @MainActor (URL) -> Void) {
        for window in NSApp.windows where window is NSPanel {
            window.orderOut(nil)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            set chosenFile to choose file with prompt "\(prompt)"
            return POSIX path of chosenFile
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !path.isEmpty else { return }
                let url = URL(fileURLWithPath: path)
                DispatchQueue.main.async {
                    completion(url)
                }
            } catch {}
        }
    }
}
