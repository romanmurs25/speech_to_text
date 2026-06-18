import Foundation

public struct MockOverlayEventSource: Sendable {
    public init() {}

    public func events() -> AsyncStream<ServerMessage> {
        AsyncStream { continuation in
            continuation.yield(.transcriptDelta(TranscriptDelta(
                clientUtteranceID: "mock-client-1",
                openAIItemID: "mock-item-1",
                sequence: 1,
                source: .systemAudio,
                speaker: .remote,
                delta: "Could you send"
            )))
            continuation.yield(.transcriptCompleted(TranscriptCompleted(
                clientUtteranceID: "mock-client-1",
                openAIItemID: "mock-item-1",
                sequence: 1,
                source: .systemAudio,
                speaker: .remote,
                transcript: "Could you send me the revised proposal by Friday?"
            )))
            continuation.yield(.overlayResult(OverlayResultMessage(
                clientUtteranceID: "mock-client-1",
                sequence: 1,
                result: OverlayResult(
                    utteranceID: "mock-item-1",
                    detectedLanguage: "en",
                    originalText: "Could you send me the revised proposal by Friday?",
                    translationRU: "Could you send me the revised proposal by Friday? in Russian",
                    translationEN: "Could you send me the revised proposal by Friday?",
                    replyNeeded: true,
                    suggestedReplyRU: "Yes, I will follow up on that.",
                    suggestedReplyEN: "Yes, I will follow up on that."
                )
            )))
            continuation.finish()
        }
    }
}
