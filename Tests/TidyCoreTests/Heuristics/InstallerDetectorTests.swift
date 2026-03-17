import Testing
@testable import TidyCore

@Suite("InstallerDetector")
struct InstallerDetectorTests {
    let detector = InstallerDetector()

    @Test("detects DMG files")
    func dmg() { #expect(detector.isInstaller(extension: "dmg") == true) }

    @Test("detects PKG files")
    func pkg() { #expect(detector.isInstaller(extension: "pkg") == true) }

    @Test("rejects non-installer extensions")
    func pdf() { #expect(detector.isInstaller(extension: "pdf") == false) }

    @Test("detects app bundles")
    func appBundle() { #expect(detector.isInstaller(extension: "app") == true) }
}
