// Sources/TidyCore/Watcher/SettleTimer.swift
import Foundation

public actor SettleTimer {
    private let settleSeconds: TimeInterval
    private var lastTouched: [String: ContinuousClock.Instant] = [:]

    public init(settleSeconds: TimeInterval = 5.0) { self.settleSeconds = settleSeconds }

    public func touch(path: String) { lastTouched[path] = .now }

    public func isSettled(path: String) -> Bool {
        guard let lastTime = lastTouched[path] else { return true }
        return (ContinuousClock.Instant.now - lastTime) >= .seconds(settleSeconds)
    }

    public func remove(path: String) { lastTouched.removeValue(forKey: path) }

    public func settledPaths() -> [String] {
        lastTouched.keys.filter { isSettled(path: $0) }
    }
}
