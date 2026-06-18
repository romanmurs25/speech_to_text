import Foundation

@MainActor
public final class BackendMicrophoneSessionContext {
    public enum Phase: Equatable, Sendable {
        case starting
        case waitingForPermission
        case startingCapture
        case listening
        case cleaningUp
        case finished
    }

    public let generation: UUID
    public let backendSessionID: UUID
    public let client: BackendWebSocketClient
    public let coordinator: AudioStreamCoordinator
    public let microphone: MicrophoneCaptureServiceProtocol
    public let pipe: BoundedAudioChunkPipe
    public let invalidationToken: SessionInvalidationToken
    public var receiveTask: Task<Void, Never>?
    public var audioProcessingTask: Task<Void, Never>?
    public var cleanupTask: Task<Void, Never>?
    public var phase: Phase = .starting
    public var microphoneCaptureStarted = false

    public init(
        generation: UUID,
        backendSessionID: UUID,
        client: BackendWebSocketClient,
        coordinator: AudioStreamCoordinator,
        microphone: MicrophoneCaptureServiceProtocol,
        pipe: BoundedAudioChunkPipe,
        invalidationToken: SessionInvalidationToken
    ) {
        self.generation = generation
        self.backendSessionID = backendSessionID
        self.client = client
        self.coordinator = coordinator
        self.microphone = microphone
        self.pipe = pipe
        self.invalidationToken = invalidationToken
    }
}
