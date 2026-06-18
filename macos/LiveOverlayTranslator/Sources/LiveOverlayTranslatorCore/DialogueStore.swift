import Foundation

public struct DialogueTurn: Codable, Equatable, Sendable {
    public let speaker: Speaker
    public let text: String

    public init(speaker: Speaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

private struct SequencedTurn: Equatable, Sendable {
    let turn: DialogueTurn
    let sequence: Int
}

public struct DialogueStore: Sendable {
    private let maxTurns: Int
    private var turns: [SequencedTurn] = []

    public init(maxTurns: Int = 10) {
        self.maxTurns = maxTurns
    }

    public mutating func addFinalizedSpeech(speaker: Speaker, text: String, sequence: Int) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        turns.append(SequencedTurn(turn: DialogueTurn(speaker: speaker, text: cleaned), sequence: sequence))
        turns.sort { $0.sequence < $1.sequence }
        if turns.count > maxTurns {
            turns.removeFirst(turns.count - maxTurns)
        }
    }

    public mutating func addSuggestedReply(ru: String, en: String, sequence: Int) {
        _ = (ru, en, sequence)
    }

    public mutating func markSuggestedReplyUsed(text: String, sequence: Int) {
        addFinalizedSpeech(speaker: .local, text: text, sequence: sequence)
    }

    public func context() -> [DialogueTurn] {
        turns.map(\.turn)
    }
}
