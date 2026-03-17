// Sources/TidyCore/Models/SizeBucket.swift
import Foundation

public enum SizeBucket: String, Codable, Sendable {
    case tiny, small, medium, large, huge

    public init(bytes: UInt64) {
        switch bytes {
        case 0..<10_240:                    self = .tiny      // < 10 KB
        case 10_240..<1_048_576:            self = .small     // 10 KB – 1 MB
        case 1_048_576..<52_428_800:        self = .medium    // 1 MB – 50 MB
        case 52_428_800..<1_073_741_824:    self = .large     // 50 MB – 1 GB
        default:                            self = .huge      // > 1 GB
        }
    }
}
