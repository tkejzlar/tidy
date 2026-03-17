import Foundation

public struct RecencyWeighter: Sendable {
    private let decayRate: Double
    public init(decayRate: Double = 0.95) { self.decayRate = decayRate }

    public func weight(daysSinceLastUse: Int) -> Double {
        pow(decayRate, Double(daysSinceLastUse))
    }

    public func weight(lastUsed: Date, now: Date = Date()) -> Double {
        let days = Calendar.current.dateComponents([.day], from: lastUsed, to: now).day ?? 0
        return weight(daysSinceLastUse: max(0, days))
    }
}
