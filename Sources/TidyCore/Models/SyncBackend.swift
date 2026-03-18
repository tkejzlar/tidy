// Sources/TidyCore/Models/SyncBackend.swift
import Foundation

public enum SyncBackend: String, Codable, Sendable {
    case icloud
    case dropbox
    case local

    public func syncDirectory(dropboxPath: String?) -> String {
        switch self {
        case .icloud:
            return NSString(string: "~/Library/Mobile Documents/iCloud~com~tidy~app/Documents").expandingTildeInPath
        case .dropbox:
            if let path = dropboxPath {
                return path + "/.tidy"
            }
            return NSString(string: "~/Dropbox/.tidy").expandingTildeInPath
        case .local:
            return NSString(string: "~/Library/Application Support/Tidy").expandingTildeInPath
        }
    }
}

public struct DeviceIdentity: Sendable {
    private static let key = "deviceId"

    public static func deviceId(from defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: key)
        return newId
    }
}
