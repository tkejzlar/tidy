// Tests/TidyCoreTests/Models/SizeBucketTests.swift
import Testing
@testable import TidyCore

@Suite("SizeBucket")
struct SizeBucketTests {
    @Test("classifies bytes into correct buckets")
    func bucketClassification() {
        #expect(SizeBucket(bytes: 500) == .tiny)           // < 10 KB
        #expect(SizeBucket(bytes: 50_000) == .small)       // 10 KB – 1 MB
        #expect(SizeBucket(bytes: 5_000_000) == .medium)   // 1 MB – 50 MB
        #expect(SizeBucket(bytes: 200_000_000) == .large)  // 50 MB – 1 GB
        #expect(SizeBucket(bytes: 2_000_000_000) == .huge) // > 1 GB
    }

    @Test("boundary values")
    func boundaries() {
        #expect(SizeBucket(bytes: 10_240) == .small)       // exactly 10 KB
        #expect(SizeBucket(bytes: 10_239) == .tiny)
        #expect(SizeBucket(bytes: 1_048_576) == .medium)   // exactly 1 MB
    }
}
