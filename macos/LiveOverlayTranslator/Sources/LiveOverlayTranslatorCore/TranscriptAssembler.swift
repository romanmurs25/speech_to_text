import Foundation

public struct TranscriptAssembler: Sendable {
    private var provisional: [String: String] = [:]
    private var completed: [String: String] = [:]

    public init() {}

    public mutating func apply(delta: TranscriptDelta) {
        provisional[delta.clientUtteranceID, default: ""] += delta.delta
    }

    public mutating func apply(completed message: TranscriptCompleted) {
        provisional.removeValue(forKey: message.clientUtteranceID)
        completed[message.clientUtteranceID] = message.transcript
    }

    public func provisionalText(for clientUtteranceID: String) -> String? {
        provisional[clientUtteranceID]
    }

    public func completedText(for clientUtteranceID: String) -> String? {
        completed[clientUtteranceID]
    }
}
