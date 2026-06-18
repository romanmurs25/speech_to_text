import Foundation
import Testing
@testable import LiveOverlayTranslatorCore

@Test
@MainActor
func backendMicrophoneSessionContextOwnsOneImmutableResourceSet() {
    let generation = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let backendSessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let token = SessionInvalidationToken()
    let client = BackendWebSocketClient(
        url: URL(string: "ws://127.0.0.1:8787/ws")!,
        transport: ContextFakeTransport()
    )
    let coordinator = AudioStreamCoordinator(
        detector: ContextFakeDetector(),
        websocket: client,
        invalidationToken: token
    )
    let microphone = ContextFakeMicrophone()
    let pipe = BoundedAudioChunkPipe(limit: 2, invalidationToken: token) {}

    let context = BackendMicrophoneSessionContext(
        generation: generation,
        backendSessionID: backendSessionID,
        client: client,
        coordinator: coordinator,
        microphone: microphone,
        pipe: pipe,
        invalidationToken: token
    )

    #expect(context.generation == generation)
    #expect(context.backendSessionID == backendSessionID)
    #expect(context.phase == .starting)
    #expect(context.invalidationToken.invalidate(reason: .userStop))
    #expect(!context.invalidationToken.invalidate(reason: .staleGeneration))
    #expect(context.invalidationToken.invalidationReason == .userStop)
}

private final class ContextFakeMicrophone: MicrophoneCaptureServiceProtocol, @unchecked Sendable {
    func requestPermission() async throws {}
    func startCapture(onChunk _: @escaping @Sendable (AudioChunk) -> Void) throws {}
    func stop() {}
}

private final class ContextFakeDetector: SpeechEndpointDetector {
    func process(samples _: [Int16], timestampMs _: Int) -> [SpeechEndpointEvent] { [] }
    func reset() {}
}

private final class ContextFakeTransport: WebSocketTransport, @unchecked Sendable {
    func connect(to _: URL) async throws {}
    func disconnect() async {}
    func sendString(_: String) async throws {}
    func sendData(_: Data) async throws {}
    func receive() async throws -> WebSocketTransportMessage {
        throw BackendWebSocketClient.ClientError.cancelled
    }
}
