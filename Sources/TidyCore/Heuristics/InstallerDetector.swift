import Foundation

public struct InstallerDetector: Sendable {
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "app"]
    public init() {}
    public func isInstaller(extension ext: String) -> Bool {
        Self.installerExtensions.contains(ext.lowercased())
    }
}
