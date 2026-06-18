import Combine
import Foundation

public enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connected
    case degraded(String)
}

public struct OverlayCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let clientUtteranceID: String
    public let openAIItemID: String
    public let sequence: Int
    public let source: AudioSource
    public let speaker: Speaker
    public var originalTranscript: String
    public var result: OverlayResult?

    public init(completed: TranscriptCompleted) {
        self.id = completed.clientUtteranceID
        self.clientUtteranceID = completed.clientUtteranceID
        self.openAIItemID = completed.openAIItemID
        self.sequence = completed.sequence
        self.source = completed.source
        self.speaker = completed.speaker
        self.originalTranscript = completed.transcript
        self.result = nil
    }
}

@MainActor
public final class OverlayState: ObservableObject {
    @Published public private(set) var cards: [OverlayCard] = []
    @Published public private(set) var provisionalText: String = ""
    @Published public private(set) var connectionStatus: ConnectionStatus = .disconnected
    @Published public private(set) var pendingTranslationIDs: Set<String> = []
    @Published public private(set) var recoverableError: String?

    private var provisionalByUtterance: [String: String] = [:]

    public init() {}

    public func apply(_ message: ServerMessage) {
        switch message {
        case let .transcriptDelta(delta):
            provisionalByUtterance[delta.clientUtteranceID, default: ""] += delta.delta
            provisionalText = provisionalByUtterance[delta.clientUtteranceID] ?? ""

        case let .transcriptCompleted(completed):
            provisionalByUtterance.removeValue(forKey: completed.clientUtteranceID)
            provisionalText = provisionalByUtterance.values.first ?? ""
            pendingTranslationIDs.insert(completed.clientUtteranceID)
            upsertCard(OverlayCard(completed: completed))

        case let .overlayResult(resultMessage):
            guard let index = cards.firstIndex(where: {
                $0.clientUtteranceID == resultMessage.clientUtteranceID &&
                $0.sequence == resultMessage.sequence
            }) else {
                return
            }
            cards[index].result = resultMessage.result
            pendingTranslationIDs.remove(resultMessage.clientUtteranceID)

        case let .recoverableError(error):
            recoverableError = error.message
            connectionStatus = .degraded(error.code)
        }
    }

    private func upsertCard(_ card: OverlayCard) {
        if let index = cards.firstIndex(where: { $0.clientUtteranceID == card.clientUtteranceID }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
        cards.sort { $0.sequence > $1.sequence }
        if cards.count > 3 {
            cards.removeLast(cards.count - 3)
        }
    }
}
