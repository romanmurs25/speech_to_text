import Foundation

public struct MockOverlayEventSource: Sendable {
    public init() {}

    public func events() -> AsyncStream<ServerMessage> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.sessionState(SessionStateMessage(
                    status: .ready,
                    sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
                )))
                continuation.yield(.transcriptDelta(TranscriptDelta(
                    clientUtteranceID: "mock-client-1",
                    openAIItemID: "mock-item-1",
                    sequence: 1,
                    source: .microphone,
                    speaker: .local,
                    delta: "Could you send"
                )))
                try? await Task.sleep(nanoseconds: 450_000_000)
                continuation.yield(.transcriptDelta(TranscriptDelta(
                    clientUtteranceID: "mock-client-1",
                    openAIItemID: "mock-item-1",
                    sequence: 1,
                    source: .microphone,
                    speaker: .local,
                    delta: " me the revised proposal by Friday?"
                )))
                try? await Task.sleep(nanoseconds: 550_000_000)
                continuation.yield(.transcriptCompleted(TranscriptCompleted(
                    clientUtteranceID: "mock-client-1",
                    openAIItemID: "mock-item-1",
                    sequence: 1,
                    source: .microphone,
                    speaker: .local,
                    transcript: "Could you send me the revised proposal by Friday?"
                )))
                try? await Task.sleep(nanoseconds: 700_000_000)
                continuation.yield(.overlayResult(OverlayResultMessage(
                    clientUtteranceID: "mock-client-1",
                    sequence: 1,
                    result: OverlayResult(
                        utteranceID: "mock-item-1",
                        detectedLanguage: "en",
                        originalText: "Could you send me the revised proposal by Friday?",
                        translationRU: "Не могли бы вы прислать мне обновлённое предложение к пятнице?",
                        translationEN: "Could you send me the revised proposal by Friday?",
                        replyNeeded: true,
                        suggestedReplyRU: "Да, я закончу правки и отправлю обновлённую версию к пятнице.",
                        suggestedReplyEN: "Yes, I'll finish the revisions and send you the updated version by Friday."
                    )
                )))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
