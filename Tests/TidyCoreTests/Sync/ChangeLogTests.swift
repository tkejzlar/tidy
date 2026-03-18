import Testing
@testable import TidyCore

@Suite("ChangeLog")
struct ChangeLogTests {
    @Test("ChangeLog round-trips through JSON")
    func jsonRoundTrip() throws {
        let ts = makeDate(timeIntervalSince1970: 1000000)
        let log = ChangeLog(
            deviceId: "test-device",
            timestamp: ts,
            patterns: [
                ChangeLogEntry(
                    fileExtension: "pdf", filenameTokens: "[\"invoice\"]",
                    sourceApp: "Safari", sizeBucket: "medium", timeBucket: "morning",
                    documentType: "invoice", sourceDomain: "email", sceneType: nil,
                    sourceFolder: "~/Downloads", destination: "~/Documents",
                    signalType: "observation", weight: 1.0, createdAt: ts
                )
            ],
            pinnedRules: [
                PinnedRuleEntry(fileExtension: "dmg", destination: "~/Apps", updatedAt: ts)
            ]
        )
        let data = try jsonEncodeISO8601(log)
        let decoded = try jsonDecodeISO8601(ChangeLog.self, from: data)
        #expect(decoded.deviceId == "test-device")
        #expect(decoded.patterns.count == 1)
        #expect(decoded.patterns[0].fileExtension == "pdf")
        #expect(decoded.pinnedRules.count == 1)
        #expect(decoded.pinnedRules[0].fileExtension == "dmg")
    }

    @Test("empty log encodes correctly")
    func emptyLog() throws {
        let log = ChangeLog(deviceId: "dev1", timestamp: makeDate(timeIntervalSince1970: 0), patterns: [])
        let data = try jsonEncodeISO8601(log)
        let decoded = try jsonDecodeISO8601(ChangeLog.self, from: data)
        #expect(decoded.patterns.isEmpty)
        #expect(decoded.pinnedRules.isEmpty)
    }

    @Test("ChangeLogEntry fields roundtrip")
    func entryFields() {
        let entry = ChangeLogEntry(
            fileExtension: "txt", filenameTokens: nil, sourceApp: nil,
            sizeBucket: nil, timeBucket: nil, documentType: nil,
            sourceDomain: nil, sceneType: nil, sourceFolder: nil,
            destination: "/docs", signalType: "observation",
            weight: 1.0, createdAt: makeDate(timeIntervalSince1970: 0)
        )
        #expect(entry.destination == "/docs")
        #expect(entry.signalType == "observation")
    }
}
