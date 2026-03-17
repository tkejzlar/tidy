// Sources/TidyCore/Operations/SignalRecorder.swift
import Foundation

public struct SignalRecorder: Sendable {
    private let knowledgeBase: KnowledgeBase
    public init(knowledgeBase: KnowledgeBase) { self.knowledgeBase = knowledgeBase }

    public func recordObservation(candidate: FileCandidate, destination: String) throws {
        try knowledgeBase.recordPattern(
            extension: candidate.fileExtension, filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp, sizeBucket: candidate.sizeBucket,
            timeBucket: candidate.timeBucket, destination: destination, signalType: .observation
        )
    }

    public func recordCorrection(candidate: FileCandidate, wrongDestination: String, correctDestination: String) throws {
        try knowledgeBase.recordPattern(
            extension: candidate.fileExtension, filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp, sizeBucket: candidate.sizeBucket,
            timeBucket: candidate.timeBucket, destination: correctDestination, signalType: .correction
        )
    }

    public func recordConfirmation(candidate: FileCandidate, destination: String) throws {
        try knowledgeBase.recordPattern(
            extension: candidate.fileExtension, filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp, sizeBucket: candidate.sizeBucket,
            timeBucket: candidate.timeBucket, destination: destination, signalType: .confirmation
        )
    }
}
