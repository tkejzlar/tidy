// Sources/TidyCore/Models/RoutingDecision.swift
import Foundation

/// A single destination with a confidence score from one layer.
public struct ScoredDestination: Sendable {
    public let path: String
    public let confidence: Double  // 0.0–1.0
    public let reason: String

    public init(path: String, confidence: Double, reason: String) {
        self.path = path
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.reason = reason
    }
}

/// The final routing decision after combining all layers.
public struct RoutingDecision: Sendable {
    public let destination: String
    public let confidence: Int  // 0–100
    public let layerBreakdown: [String: Double]  // layer name → weighted score
    public let reason: String

    public var tier: ConfidenceTier {
        ConfidenceTier(confidence: confidence)
    }
}

public enum ConfidenceTier: Sendable {
    case autoMove    // 80–100
    case suggest     // 50–79
    case ask         // 0–49

    public init(confidence: Int) {
        switch confidence {
        case 80...100: self = .autoMove
        case 50..<80:  self = .suggest
        default:       self = .ask
        }
    }
}
