import Foundation
import Testing
@testable import LiveOverlayTranslatorCore

@Test
func audioStreamCoordinatorDoesNotCommitAfterSessionInvalidation() async throws {
    let token = SessionInvalidationToken()
    let detector = ScriptedSpeechEndpointDetector(events: [
        [.speechStarted(startedAtMs: 100, initialSamples: [1, 2, 3])],
        [.speechEnded(endedAtMs: 250)]
    ])
    let transport = CoordinatorFakeTransport()
    let websocket = BackendWebSocketClient(
        url: URL(string: "ws://127.0.0.1:8787/ws")!,
        transport: transport
    )
    let coordinator = AudioStreamCoordinator(
        detector: detector,
        websocket: websocket,
        streamSettings: AudioStreamSettings(),
        invalidationToken: token
    )

    try await coordinator.start(
        sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!,
        source: .microphone
    )
    try await coordinator.process(AudioChunk(source: .microphone, pcmSamples: [1, 2, 3], timestampMs: 100))
    token.invalidate(reason: .audioPipelineOverflow)
    try await coordinator.process(AudioChunk(source: .microphone, pcmSamples: [], timestampMs: 250))

    let controls = try transport.decodedControls()
    #expect(controls.filter(\.isUtteranceCommit).isEmpty)
    #expect(controls.filter(\.isUtteranceCancel).count == 1)
    #expect(transport.didDisconnect == false)
}

@Test
func audioStreamCoordinatorStopDisconnectsEvenWhenStopStreamFails() async throws {
    let detector = ScriptedSpeechEndpointDetector(events: [
        [.speechStarted(startedAtMs: 100, initialSamples: [1, 2, 3])]
    ])
    let transport = CoordinatorFakeTransport()
    transport.throwOnStopStream = true
    let websocket = BackendWebSocketClient(
        url: URL(string: "ws://127.0.0.1:8787/ws")!,
        transport: transport
    )
    let coordinator = AudioStreamCoordinator(
        detector: detector,
        websocket: websocket
    )

    try await coordinator.start(
        sessionID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!,
        source: .microphone
    )
    try await coordinator.process(AudioChunk(source: .microphone, pcmSamples: [1, 2, 3], timestampMs: 100))

    do {
        try await coordinator.stop(source: .microphone)
        Issue.record("Expected stop_stream failure to be rethrown after disconnect")
    } catch {
        #expect(transport.didDisconnect)
    }

    let controls = try transport.decodedControls()
    #expect(controls.filter(\.isUtteranceCancel).count == 1)
}

private final class ScriptedSpeechEndpointDetector: SpeechEndpointDetector {
    private var events: [[SpeechEndpointEvent]]

    init(events: [[SpeechEndpointEvent]]) {
        self.events = events
    }

    func process(samples _: [Int16], timestampMs _: Int) -> [SpeechEndpointEvent] {
        if events.isEmpty {
            return []
        }
        return events.removeFirst()
    }

    func reset() {}
}

private final class CoordinatorFakeTransport: WebSocketTransport, @unchecked Sendable {
    var didConnect = false
    var didDisconnect = false
    var sentStrings: [String] = []
    var sentData: [Data] = []
    var throwOnStopStream = false

    func connect(to _: URL) async throws {
        didConnect = true
    }

    func disconnect() async {
        didDisconnect = true
    }

    func sendString(_ text: String) async throws {
        if throwOnStopStream, text.contains("\"stop_stream\"") {
            throw BackendWebSocketClient.ClientError.notConnected
        }
        sentStrings.append(text)
    }

    func sendData(_ data: Data) async throws {
        sentData.append(data)
    }

    func receive() async throws -> WebSocketTransportMessage {
        throw BackendWebSocketClient.ClientError.cancelled
    }

    func decodedControls() throws -> [ClientControlMessage] {
        try sentStrings.map { text in
            try JSONDecoder.protocolDecoder.decode(ClientControlMessage.self, from: Data(text.utf8))
        }
    }
}

private extension ClientControlMessage {
    var isUtteranceCommit: Bool {
        if case .utteranceCommit = self {
            return true
        }
        return false
    }

    var isUtteranceCancel: Bool {
        if case .utteranceCancel = self {
            return true
        }
        return false
    }
}
