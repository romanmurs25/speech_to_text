import Foundation
import Testing
@testable import LiveOverlayTranslatorCore

@Test
func helloMessageRoundTrips() throws {
    let sessionID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    let message = ClientControlMessage.hello(
        HelloMessage(protocolVersion: 1, clientVersion: "0.1.0", sessionID: sessionID)
    )

    let data = try JSONEncoder.protocolEncoder.encode(message)
    let decoded = try JSONDecoder.protocolDecoder.decode(ClientControlMessage.self, from: data)

    #expect(decoded == message)
}

@Test
func sessionStateReadyDecodesFirstBackendResponse() throws {
    let data = """
    {
      "type": "session_state",
      "status": "ready",
      "session_id": "550e8400-e29b-41d4-a716-446655440000"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder.protocolDecoder.decode(ServerMessage.self, from: data)

    #expect(decoded == .sessionState(SessionStateMessage(
        status: .ready,
        sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    )))
}

@Test
func serverMessagesRoundTripEverySupportedCase() throws {
    let sessionID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    let result = OverlayResult(
        utteranceID: "item_003",
        detectedLanguage: "en",
        originalText: "Could you send it?",
        translationRU: "Не могли бы вы прислать это?",
        translationEN: "Could you send it?",
        replyNeeded: true,
        suggestedReplyRU: "Да, отправлю сегодня.",
        suggestedReplyEN: "Yes, I will send it today."
    )
    let messages: [ServerMessage] = [
        .sessionState(SessionStateMessage(status: .ready, sessionID: sessionID)),
        .transcriptDelta(TranscriptDelta(
            clientUtteranceID: "client-1",
            openAIItemID: "item-1",
            sequence: 1,
            source: .microphone,
            speaker: .local,
            delta: "Hello"
        )),
        .transcriptCompleted(TranscriptCompleted(
            clientUtteranceID: "client-1",
            openAIItemID: "item-1",
            sequence: 1,
            source: .microphone,
            speaker: .local,
            transcript: "Hello"
        )),
        .overlayResult(OverlayResultMessage(clientUtteranceID: "client-1", sequence: 1, result: result)),
        .recoverableError(RecoverableErrorMessage(
            code: "translation_failed",
            message: "Translation is temporarily unavailable.",
            clientUtteranceID: "client-1"
        )),
        .fatalError(FatalErrorMessage(code: "protocol_violation", message: "Malformed client message."))
    ]

    for message in messages {
        let data = try JSONEncoder.protocolEncoder.encode(message)
        let decoded = try JSONDecoder.protocolDecoder.decode(ServerMessage.self, from: data)
        #expect(decoded == message)
    }
}

@Test
func overlayResultMessageRoundTrips() throws {
    let result = OverlayResult(
        utteranceID: "item_003",
        detectedLanguage: "en",
        originalText: "Could you send it?",
        translationRU: "Could you send it? in Russian",
        translationEN: "Could you send it?",
        replyNeeded: true,
        suggestedReplyRU: "Yes, I will send it today.",
        suggestedReplyEN: "Yes, I will send it today."
    )
    let message = ServerMessage.overlayResult(
        OverlayResultMessage(clientUtteranceID: "client-1", sequence: 2, result: result)
    )

    let data = try JSONEncoder.protocolEncoder.encode(message)
    let decoded = try JSONDecoder.protocolDecoder.decode(ServerMessage.self, from: data)

    #expect(decoded == message)
}
