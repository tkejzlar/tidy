import Testing
@testable import TidyCore

@Suite("SyncBackend")
struct SyncBackendTests {
    @Test("raw values are stable strings")
    func rawValues() {
        #expect(SyncBackend.icloud.rawValue == "icloud")
        #expect(SyncBackend.dropbox.rawValue == "dropbox")
        #expect(SyncBackend.local.rawValue == "local")
    }

    @Test("syncDirectory returns correct path for dropbox")
    func dropboxPath() {
        let dir = SyncBackend.dropbox.syncDirectory(dropboxPath: "/Users/test/Dropbox")
        #expect(dir == "/Users/test/Dropbox/.tidy")
    }

    @Test("syncDirectory returns correct path for local")
    func localPath() {
        let dir = SyncBackend.local.syncDirectory(dropboxPath: nil)
        #expect(dir.hasSuffix("Library/Application Support/Tidy"))
    }

    @Test("syncDirectory returns correct path for icloud")
    func icloudPath() {
        let dir = SyncBackend.icloud.syncDirectory(dropboxPath: nil)
        #expect(dir.contains("Mobile Documents/iCloud~com~tidy~app"))
    }

    @Test("DeviceId generates stable UUID")
    func deviceIdStability() {
        let (defaults, suiteName) = makeTestUserDefaults()
        defer { cleanupTestUserDefaults(suiteName: suiteName) }
        let id1 = DeviceIdentity.deviceId(from: defaults)
        let id2 = DeviceIdentity.deviceId(from: defaults)
        #expect(id1 == id2)
        #expect(!id1.isEmpty)
    }
}
