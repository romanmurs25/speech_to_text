import Foundation

public actor AudioStreamCoordinator {
    private let detector: SpeechEndpointDetector
    private let websocket: BackendWebSocketClient
    private var sequence = 0
    private var activeUtteranceID: String?

    public init(detector: SpeechEndpointDetector, websocket: BackendWebSocketClient) {
        self.detector = detector
        self.websocket = websocket
    }

    public func start(sessionID: UUID, clientVersion: String = "0.1.0", source: AudioSource) async throws {
        await websocket.connect()
        try await websocket.send(.hello(HelloMessage(
            protocolVersion: 1,
            clientVersion: clientVersion,
            sessionID: sessionID
        )))
        try await websocket.send(.startStream(StartStreamMessage(source: source)))
    }

    public func process(_ chunk: AudioChunk) async throws {
        let events = detector.process(samples: chunk.pcmSamples, timestampMs: chunk.timestampMs)
        for event in events {
            switch event {
            case .started:
                sequence += 1
                let utteranceID = UUID().uuidString
                activeUtteranceID = utteranceID
                try await websocket.send(.utteranceStart(UtteranceStartMessage(
                    clientUtteranceID: utteranceID,
                    source: chunk.source,
                    speaker: chunk.source == .microphone ? .local : .remote,
                    sequence: sequence,
                    startedAtMs: chunk.timestampMs
                )))
            case let .ended(utterance):
                guard let activeUtteranceID else { continue }
                try await websocket.sendAudio(pcmData(from: utterance.samples))
                try await websocket.send(.utteranceCommit(UtteranceCommitMessage(
                    clientUtteranceID: activeUtteranceID,
                    sequence: sequence,
                    endedAtMs: utterance.endedAtMs
                )))
                self.activeUtteranceID = nil
            }
        }
    }

    public func stop(source: AudioSource) async throws {
        try await websocket.send(.stopStream(StopStreamMessage(source: source)))
        await websocket.disconnect()
    }

    private func pcmData(from samples: [Int16]) -> Data {
        var littleEndian = samples.map { $0.littleEndian }
        return Data(bytes: &littleEndian, count: littleEndian.count * MemoryLayout<Int16>.size)
    }
}
