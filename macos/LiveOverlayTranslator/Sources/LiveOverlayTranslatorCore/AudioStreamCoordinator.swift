import Foundation

public struct AudioStreamSettings: Equatable, Sendable {
    public var sampleRate: Int = 24_000
    public var frameDurationMs: Int = 100
    public var maxFrameBytes: Int = 256 * 1_024

    public init() {}

    public var maxSamplesPerFrame: Int {
        max(1, min(sampleRate * frameDurationMs / 1_000, maxFrameBytes / MemoryLayout<Int16>.size))
    }
}

public struct PCMFrameChunker: Sendable {
    private let maxSamplesPerFrame: Int

    public init(settings: AudioStreamSettings = AudioStreamSettings()) {
        self.maxSamplesPerFrame = settings.maxSamplesPerFrame
    }

    public func frames(from samples: [Int16]) -> [Data] {
        guard !samples.isEmpty else { return [] }

        var frames: [Data] = []
        var index = 0
        while index < samples.count {
            let end = min(index + maxSamplesPerFrame, samples.count)
            frames.append(pcmData(from: samples[index..<end]))
            index = end
        }
        return frames
    }

    private func pcmData(from samples: ArraySlice<Int16>) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }
}

public actor AudioStreamCoordinator {
    private let detector: SpeechEndpointDetector
    private let websocket: BackendWebSocketClient
    private let chunker: PCMFrameChunker
    private let invalidationToken: SessionInvalidationToken?
    private var sequence = 0
    private var activeUtteranceID: String?
    private var activeSource: AudioSource?

    public init(
        detector: SpeechEndpointDetector,
        websocket: BackendWebSocketClient,
        streamSettings: AudioStreamSettings = AudioStreamSettings(),
        invalidationToken: SessionInvalidationToken? = nil
    ) {
        self.detector = detector
        self.websocket = websocket
        self.chunker = PCMFrameChunker(settings: streamSettings)
        self.invalidationToken = invalidationToken
    }

    public func start(sessionID: UUID, clientVersion: String = "0.1.0", source: AudioSource) async throws {
        try await throwIfInvalidated()
        try await websocket.connect()
        try await throwIfInvalidated()
        try await websocket.send(.hello(HelloMessage(
            protocolVersion: 1,
            clientVersion: clientVersion,
            sessionID: sessionID
        )))
        try await throwIfInvalidated()
        try await websocket.send(.startStream(StartStreamMessage(source: source)))
        try await throwIfInvalidated()
    }

    public func process(_ chunk: AudioChunk) async throws {
        if await cancelIfInvalidated() {
            return
        }
        let events = detector.process(samples: chunk.pcmSamples, timestampMs: chunk.timestampMs)
        for event in events {
            if await cancelIfInvalidated() {
                return
            }
            switch event {
            case let .speechStarted(startedAtMs, initialSamples):
                guard activeUtteranceID == nil else { continue }
                sequence += 1
                let utteranceID = UUID().uuidString
                activeUtteranceID = utteranceID
                activeSource = chunk.source
                try await websocket.send(.utteranceStart(UtteranceStartMessage(
                    clientUtteranceID: utteranceID,
                    source: chunk.source,
                    speaker: chunk.source == .microphone ? .local : .remote,
                    sequence: sequence,
                    startedAtMs: startedAtMs
                )))
                if await cancelIfInvalidated() {
                    return
                }
                try await sendSamples(initialSamples)

            case let .speechSamples(samples):
                guard activeUtteranceID != nil else { continue }
                try await sendSamples(samples)

            case let .speechEnded(endedAtMs):
                guard let activeUtteranceID else { continue }
                if await cancelIfInvalidated() {
                    return
                }
                try await websocket.send(.utteranceCommit(UtteranceCommitMessage(
                    clientUtteranceID: activeUtteranceID,
                    sequence: sequence,
                    endedAtMs: endedAtMs
                )))
                self.activeUtteranceID = nil
                self.activeSource = nil
                try await throwIfInvalidated()

            case .utteranceDiscarded:
                try await cancelActiveUtterance(reason: .minimumSpeechDurationNotMet)
            }
        }
    }

    public func cancelActiveUtterance(reason: UtteranceCancelReason) async throws {
        detector.reset()
        guard let activeUtteranceID else {
            activeSource = nil
            return
        }

        let cancel = UtteranceCancelMessage(
            clientUtteranceID: activeUtteranceID,
            sequence: sequence,
            reason: reason
        )
        self.activeUtteranceID = nil
        self.activeSource = nil
        try await websocket.send(.utteranceCancel(cancel))
    }

    public func stop(source: AudioSource) async throws {
        var firstError: Error?
        do {
            try await cancelActiveUtterance(reason: .userInterrupted)
        } catch {
            firstError = error
        }
        do {
            try await websocket.send(.stopStream(StopStreamMessage(source: source)))
        } catch {
            if firstError == nil {
                firstError = error
            }
        }
        await websocket.disconnect()
        detector.reset()
        activeUtteranceID = nil
        activeSource = nil
        if let firstError {
            throw firstError
        }
    }

    private func sendSamples(_ samples: [Int16]) async throws {
        for frame in chunker.frames(from: samples) {
            if await cancelIfInvalidated() {
                return
            }
            try await websocket.sendAudio(frame)
            try await throwIfInvalidated()
        }
    }

    private func cancelIfInvalidated() async -> Bool {
        guard invalidationToken?.isInvalidated == true else {
            return false
        }
        let reason = invalidationToken?.invalidationReason?.utteranceCancelReason ?? .captureInterrupted
        try? await cancelActiveUtterance(reason: reason)
        return true
    }

    private func throwIfInvalidated() async throws {
        if await cancelIfInvalidated() {
            throw BackendWebSocketClient.ClientError.cancelled
        }
    }
}
