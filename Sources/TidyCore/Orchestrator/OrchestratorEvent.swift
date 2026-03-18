// Sources/TidyCore/Orchestrator/OrchestratorEvent.swift
import Foundation

public enum OrchestratorEvent: Sendable {
    case autoMoved(move: MoveRecord, decision: RoutingDecision)
    case suggested(candidate: FileCandidate, decision: RoutingDecision)
    case newFile(candidate: FileCandidate)
    case undone(originalMove: MoveRecord)
    case observed(filename: String, destination: String)
    case learnedMove(filename: String, source: String, destination: String)
}
