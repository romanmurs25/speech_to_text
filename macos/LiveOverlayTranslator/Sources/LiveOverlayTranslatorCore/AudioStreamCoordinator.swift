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
    private struct ActiveUtterance {
        let id: String
        let source: AudioSource
        let arbiter: SessionCommitArbiter
    }

    private enum UtteranceLifecycle {
        case idle
        case active(ActiveUtterance)
        case cancelling(ActiveUtterance)
        case commitAdmitted(ActiveUtterance)
        case commitInFlight(ActiveUtterance)
        case committed(ActiveUtterance)
        case finished

        var canStartNewUtterance: Bool {
            switch self {
            case .idle, .finished:
                return true
            case .active, .cancelling, .commitAdmitted, .commitInFlight, .committed:
                return false
            }
        }
    }

    private let detector: SpeechEndpointDetector
    private let websocket: BackendWebSocketClient
    private let chunker: PCMFrameChunker
    private let invalidationToken: SessionInvalidationToken?
    private var sequence = 0
    private var utteranceState: UtteranceLifecycle = .idle

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
                guard utteranceState.canStartNewUtterance else { continue }
                sequence += 1
                let utteranceID = UUID().uuidString
                let active = ActiveUtterance(
                    id: utteranceID,
                    source: chunk.source,
                    arbiter: SessionCommitArbiter()
                )
                utteranceState = .active(active)
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
                guard case .active = utteranceState else { continue }
                try await sendSamples(samples)

            case let .speechEnded(endedAtMs):
                guard case let .active(active) = utteranceState else { continue }
                if await cancelIfInvalidated() {
                    return
                }
                guard active.arbiter.tryAdmitCommit() else {
                    return
                }
                utteranceState = .commitAdmitted(active)
                _ = active.arbiter.markCommitSendStarted()
                utteranceState = .commitInFlight(active)
                try await websocket.send(.utteranceCommit(UtteranceCommitMessage(
                    clientUtteranceID: active.id,
                    sequence: sequence,
                    endedAtMs: endedAtMs
                )))
                _ = active.arbiter.markCommitSendCompleted()
                utteranceState = .committed(active)
                try await throwIfInvalidated()
                _ = active.arbiter.finish()
                utteranceState = .finished

            case .utteranceDiscarded:
                try await cancelActiveUtterance(reason: .minimumSpeechDurationNotMet)
            }
        }
    }

    public func cancelActiveUtterance(reason: UtteranceCancelReason) async throws {
        detector.reset()
        guard case let .active(active) = utteranceState else {
            return
        }

        _ = active.arbiter.invalidate(reason: reason.sessionInvalidationReason)
        utteranceState = .cancelling(active)
        let cancel = UtteranceCancelMessage(
            clientUtteranceID: active.id,
            sequence: sequence,
            reason: reason
        )
        try await websocket.send(.utteranceCancel(cancel))
        _ = active.arbiter.finish()
        utteranceState = .finished
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
        utteranceState = .idle
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
        let invalidationReason = invalidationToken?.invalidationReason ?? .captureInterrupted
        switch utteranceState {
        case let .active(active):
            _ = active.arbiter.invalidate(reason: invalidationReason)
            try? await cancelActiveUtterance(reason: invalidationReason.utteranceCancelReason)
        case let .commitAdmitted(active), let .commitInFlight(active), let .committed(active):
            _ = active.arbiter.invalidate(reason: invalidationReason)
            _ = active.arbiter.finish()
            utteranceState = .finished
        case let .cancelling(active):
            _ = active.arbiter.invalidate(reason: invalidationReason)
        case .idle, .finished:
            break
        }
        return true
    }

    private func throwIfInvalidated() async throws {
        if await cancelIfInvalidated() {
            throw BackendWebSocketClient.ClientError.cancelled
        }
    }
}

private extension UtteranceCancelReason {
    var sessionInvalidationReason: SessionInvalidationReason {
        switch self {
        case .minimumSpeechDurationNotMet:
            return .captureInterrupted
        case .audioPipelineOverflow:
            return .audioPipelineOverflow
        case .captureInterrupted:
            return .captureInterrupted
        case .userInterrupted:
            return .userStop
        case .applicationShutdown:
            return .applicationShutdown
        }
    }
}
