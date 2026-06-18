import Foundation
import Testing
@testable import LiveOverlayTranslatorCore

@Test
func backendWebSocketClientUsesTransportAndDecodesSessionState() async throws {
    let transport = FakeWebSocketTransport()
    transport.incoming = [
        .string("""
        {
          "type": "session_state",
          "status": "ready",
          "session_id": "550e8400-e29b-41d4-a716-446655440000"
        }
        """)
    ]
    let client = BackendWebSocketClient(
        url: URL(string: "ws://127.0.0.1:8787/ws")!,
        transport: transport
    )

    try await client.connect()
    try await client.send(.hello(HelloMessage(
        protocolVersion: 1,
        clientVersion: "0.1.0",
        sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
    )))
    let stream = await client.receiveMessages()
    for try await message in stream {
        #expect(message == .sessionState(SessionStateMessage(
            status: .ready,
            sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        )))
        break
    }

    #expect(transport.didConnect)
    #expect(transport.sentStrings.count == 1)
}

@Test
func backendWebSocketClientSendsBoundedBinaryFrames() async throws {
    let transport = FakeWebSocketTransport()
    let client = BackendWebSocketClient(
        url: URL(string: "ws://127.0.0.1:8787/ws")!,
        transport: transport
    )

    try await client.connect()
    try await client.sendAudio(Data([1, 2, 3, 4]))

    #expect(transport.sentData == [Data([1, 2, 3, 4])])
}

final class FakeWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    var didConnect = false
    var didDisconnect = false
    var sentStrings: [String] = []
    var sentData: [Data] = []
    var incoming: [WebSocketTransportMessage] = []

    func connect(to url: URL) async throws {
        didConnect = true
    }

    func disconnect() async {
        didDisconnect = true
    }

    func sendString(_ text: String) async throws {
        sentStrings.append(text)
    }

    func sendData(_ data: Data) async throws {
        sentData.append(data)
    }

    func receive() async throws -> WebSocketTransportMessage {
        guard !incoming.isEmpty else {
            throw BackendWebSocketClient.ClientError.cancelled
        }
        return incoming.removeFirst()
    }
}
