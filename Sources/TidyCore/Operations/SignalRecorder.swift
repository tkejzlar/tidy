// Sources/TidyCore/Operations/SignalRecorder.swift
import Foundation

public struct SignalRecorder: Sendable {
    private let knowledgeBase: KnowledgeBase
    public init(knowledgeBase: KnowledgeBase) { self.knowledgeBase = knowledgeBase }

    // MARK: - EnrichedFileContext methods

    public func recordObservation(context: EnrichedFileContext, destination: String) throws {
        let candidate = context.candidate
        let sourceFolder = (candidate.path as NSString).deletingLastPathComponent
        try knowledgeBase.recordPattern(
            extension: candidate.fileExtension,
            filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp,
            sizeBucket: candidate.sizeBucket,
            timeBucket: candidate.timeBucket,
            documentType: context.imageAnalysis?.sceneType.rawValue,
            sourceDomain: context.downloadContext?.sourceCategory.rawValue,
            sceneType: context.imageAnalysis?.sceneType.rawValue,
            sourceFolder: sourceFolder,
            destination: destination,
            signalType: .observation
        )
    }

    public func recordCorrection(context: EnrichedFileContext, wrongDestination: String, correctDestination: String) throws {
        let candidate = context.candidate
        let sourceFolder = (candidate.path as NSString).deletingLastPathComponent
        try knowledgeBase.recordPattern(
            extension: candidate.fileExtension,
            filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp,
            sizeBucket: candidate.sizeBucket,
            timeBucket: candidate.timeBucket,
            documentType: context.imageAnalysis?.sceneType.rawValue,
            sourceDomain: context.downloadContext?.sourceCategory.rawValue,
            sceneType: context.imageAnalysis?.sceneType.rawValue,
            sourceFolder: sourceFolder,
            destination: correctDestination,
            signalType: .correction
        )
    }

    public func recordConfirmation(context: EnrichedFileContext, destination: String) throws {
        let candidate = context.candidate
        let sourceFolder = (candidate.path as NSString).deletingLastPathComponent
        try knowledgeBase.recordPattern(
            extension: candidate.fileExtension,
            filenameTokens: candidate.filenameTokens,
            sourceApp: candidate.sourceApp,
            sizeBucket: candidate.sizeBucket,
            timeBucket: candidate.timeBucket,
            documentType: context.imageAnalysis?.sceneType.rawValue,
            sourceDomain: context.downloadContext?.sourceCategory.rawValue,
            sceneType: context.imageAnalysis?.sceneType.rawValue,
            sourceFolder: sourceFolder,
            destination: destination,
            signalType: .confirmation
        )
    }

    // MARK: - Legacy FileCandidate methods (delegate to EnrichedFileContext methods)

    public func recordObservation(candidate: FileCandidate, destination: String) throws {
        try recordObservation(context: EnrichedFileContext(candidate: candidate), destination: destination)
    }

    public func recordCorrection(candidate: FileCandidate, wrongDestination: String, correctDestination: String) throws {
        try recordCorrection(context: EnrichedFileContext(candidate: candidate), wrongDestination: wrongDestination, correctDestination: correctDestination)
    }

    public func recordConfirmation(candidate: FileCandidate, destination: String) throws {
        try recordConfirmation(context: EnrichedFileContext(candidate: candidate), destination: destination)
    }
}
