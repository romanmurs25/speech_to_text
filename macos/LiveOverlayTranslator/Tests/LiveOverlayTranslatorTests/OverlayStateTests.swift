import Testing
@testable import LiveOverlayTranslatorCore

@MainActor
@Test
func appliesSessionStateAndFatalErrorTransitions() {
    let state = OverlayState()
    state.apply(.sessionState(SessionStateMessage(
        status: .ready,
        sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    )))
    #expect(state.connectionStatus == .connected)

    state.apply(.sessionState(SessionStateMessage(
        status: .closed,
        sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    )))
    #expect(state.connectionStatus == .closed)

    state.apply(.fatalError(FatalErrorMessage(
        code: "protocol_violation",
        message: "Malformed client message."
    )))
    #expect(state.connectionStatus == .failed("protocol_violation"))
    #expect(state.recoverableError == "Malformed client message.")
}

@MainActor
@Test
func staleResultForUnknownUtteranceDoesNotOverwriteNewerCard() {
    let state = OverlayState()
    state.apply(.transcriptCompleted(TranscriptCompleted(
        clientUtteranceID: "client-2",
        openAIItemID: "item-2",
        sequence: 2,
        source: .systemAudio,
        speaker: .remote,
        transcript: "Newer utterance"
    )))

    state.apply(.overlayResult(OverlayResultMessage(
        clientUtteranceID: "client-1",
        sequence: 1,
        result: OverlayResult(
            utteranceID: "item-1",
            detectedLanguage: "en",
            originalText: "Older utterance",
            translationRU: "older ru",
            translationEN: "older en",
            replyNeeded: false,
            suggestedReplyRU: "",
            suggestedReplyEN: ""
        )
    )))

    #expect(state.cards.count == 1)
    #expect(state.cards.first?.clientUtteranceID == "client-2")
    #expect(state.cards.first?.result == nil)
}

@MainActor
@Test
func keepsMostRecentThreeFinalizedCards() {
    let state = OverlayState()
    for sequence in 1...4 {
        state.apply(.transcriptCompleted(TranscriptCompleted(
            clientUtteranceID: "client-\(sequence)",
            openAIItemID: "item-\(sequence)",
            sequence: sequence,
            source: .microphone,
            speaker: .local,
            transcript: "Turn \(sequence)"
        )))
    }

    #expect(state.cards.map(\.sequence) == [4, 3, 2])
}
