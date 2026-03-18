import Testing
@testable import TidyCore

@Suite("WatchedFolder")
struct WatchedFolderTests {
    @Test("FolderRole raw values are stable strings")
    func folderRoleRawValues() {
        #expect(FolderRole.inbox.rawValue == "inbox")
        #expect(FolderRole.archive.rawValue == "archive")
        #expect(FolderRole.watchOnly.rawValue == "watchOnly")
    }

    @Test("WatchedFolder round-trips through JSON encoding")
    func jsonRoundTrip() throws {
        let folder = WatchedFolder(
            url: makeFileURL(path: "/Users/test/Downloads"),
            role: .inbox,
            isEnabled: true,
            ignorePatterns: ["*.log", "node_modules"]
        )
        let data = try jsonEncode(folder)
        let decoded = try jsonDecode(WatchedFolder.self, from: data)
        #expect(decoded.role == .inbox)
        #expect(decoded.isEnabled == true)
        #expect(decoded.ignorePatterns == ["*.log", "node_modules"])
    }

    @Test("WatchedFolder defaults to enabled with no ignore patterns")
    func defaults() {
        let folder = WatchedFolder(url: makeFileURL(path: "/tmp/test"))
        #expect(folder.role == .inbox)
        #expect(folder.isEnabled == true)
        #expect(folder.ignorePatterns.isEmpty)
    }

    @Test("WatchedFolder Identifiable uses path")
    func identifiable() {
        let folder = WatchedFolder(url: makeFileURL(path: "/Users/test/Downloads"))
        #expect(folder.id == "/Users/test/Downloads")
    }

    @Test("JSON array of WatchedFolder round-trips")
    func arrayRoundTrip() throws {
        let folders = [
            WatchedFolder(url: makeFileURL(path: "/Users/test/Downloads"), role: .inbox),
            WatchedFolder(url: makeFileURL(path: "/Users/test/Desktop"), role: .inbox),
            WatchedFolder(url: makeFileURL(path: "/Users/test/Documents"), role: .archive),
        ]
        let data = try jsonEncode(folders)
        let decoded = try jsonDecode([WatchedFolder].self, from: data)
        #expect(decoded.count == 3)
        #expect(decoded[2].role == .archive)
    }
}
