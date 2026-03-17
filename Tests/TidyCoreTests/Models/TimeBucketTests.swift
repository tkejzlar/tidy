// Tests/TidyCoreTests/Models/TimeBucketTests.swift
import Testing
@testable import TidyCore

@Suite("TimeBucket")
struct TimeBucketTests {
    @Test("classifies hours into buckets")
    func hourClassification() {
        #expect(TimeBucket(hour: 7) == .morning)    // 6–11
        #expect(TimeBucket(hour: 12) == .midday)    // 12–13
        #expect(TimeBucket(hour: 15) == .afternoon) // 14–17
        #expect(TimeBucket(hour: 19) == .evening)   // 18–21
        #expect(TimeBucket(hour: 2) == .night)      // 22–5
    }
}
