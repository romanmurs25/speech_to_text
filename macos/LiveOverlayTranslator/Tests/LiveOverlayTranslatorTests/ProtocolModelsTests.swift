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
