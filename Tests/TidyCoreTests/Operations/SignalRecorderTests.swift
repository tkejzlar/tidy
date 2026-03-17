import Testing
@testable import TidyCore

@Suite("SignalRecorder")
struct SignalRecorderTests {
    @Test("records observation when user manually moves a file")
    func observation() throws {
        let kb = try KnowledgeBase.inMemory()
        let recorder = SignalRecorder(knowledgeBase: kb)
        let candidate = FileCandidate(path: "/Downloads/invoice.pdf", fileSize: 50_000)
        try recorder.recordObservation(candidate: candidate, destination: "~/Documents/Finance")
        let patterns = try kb.patterns(forExtension: "pdf")
        #expect(patterns.count == 1)
        #expect(patterns[0].destination == "~/Documents/Finance")
        #expect(patterns[0].signalType == .observation)
        #expect(patterns[0].weight == 1.0)
    }

    @Test("records correction with 3x weight")
    func correction() throws {
        let kb = try KnowledgeBase.inMemory()
        let recorder = SignalRecorder(knowledgeBase: kb)
        let candidate = FileCandidate(path: "/Downloads/report.pdf", fileSize: 1_000_000)
        try recorder.recordCorrection(candidate: candidate, wrongDestination: "~/Work", correctDestination: "~/Finance")
        let patterns = try kb.patterns(forExtension: "pdf")
        let c = patterns.first { $0.signalType == .correction }
        #expect(c != nil)
        #expect(c!.destination == "~/Finance")
        #expect(c!.weight == 3.0)
    }

    @Test("records confirmation")
    func confirmation() throws {
        let kb = try KnowledgeBase.inMemory()
        let recorder = SignalRecorder(knowledgeBase: kb)
        let candidate = FileCandidate(path: "/Downloads/photo.jpg", fileSize: 2_000_000)
        try recorder.recordConfirmation(candidate: candidate, destination: "~/Pictures")
        let patterns = try kb.patterns(forExtension: "jpg")
        #expect(patterns.count == 1)
        #expect(patterns[0].signalType == .confirmation)
    }
}
