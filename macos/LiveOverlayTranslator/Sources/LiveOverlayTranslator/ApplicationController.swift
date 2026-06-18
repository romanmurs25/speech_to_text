import AppKit
import Combine
import Foundation
import LiveOverlayTranslatorCore

enum ApplicationMode: String, CaseIterable, Identifiable {
    case localMock
    case backend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localMock:
            "Local Mock"
        case .backend:
            "Backend"
        }
    }
}

enum ApplicationRunState: String {
    case idle
    case connecting
    case connected
    case listening
    case stopping
    case failed
}

enum MicrophoneRunState: String {
    case idle
    case requestingPermission
    case listening
    case interrupted
    case stopped
}

@MainActor
final class ApplicationController: ObservableObject {
    private enum DefaultsKey {
        static let mode = "LiveOverlayTranslator.mode"
        static let backendURL = "LiveOverlayTranslator.backendURL"
    }

    let overlayState = OverlayState()

    @Published var mode: ApplicationMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.mode)
        }
    }

    @Published var backendURLString: String {
        didSet {
            UserDefaults.standard.set(backendURLString, forKey: DefaultsKey.backendURL)
        }
    }

    @Published private(set) var runState: ApplicationRunState = .idle
    @Published private(set) var microphoneState: MicrophoneRunState = .idle
    @Published private(set) var lastError: String?

    private var overlayController: OverlayWindowController?
    private var shortcutController: GlobalShortcutController?
    private let cleanShareCoordinator = CleanShareCoordinator()
    private var microphoneService: MicrophoneAudioCaptureService?
    private var backendClient: BackendWebSocketClient?
    private var audioCoordinator: AudioStreamCoordinator?
    private var receiveTask: Task<Void, Never>?
    private var audioProcessingTask: Task<Void, Never>?
    private var mockTask: Task<Void, Never>?
    private var audioPipe: BoundedAudioChunkPipe?
    private var sessionID = UUID()
    private var sessionGeneration = UUID()
    private var isCleaningUp = false

    init(defaults: UserDefaults = .standard) {
        if let storedMode = defaults.string(forKey: DefaultsKey.mode),
           let mode = ApplicationMode(rawValue: storedMode) {
            self.mode = mode
        } else {
            self.mode = .localMock
        }
        self.backendURLString = defaults.string(forKey: DefaultsKey.backendURL) ?? "ws://127.0.0.1:8787/ws"
    }

    func applicationDidFinishLaunching() {
        let controller = OverlayWindowController(state: overlayState)
        overlayController = controller
        controller.show()

        shortcutController = GlobalShortcutController(
            toggleOverlay: { [weak controller] in controller?.toggleVisibility() },
            emergencyHide: { [weak self] in
                self?.overlayController?.hide()
                self?.cleanShareCoordinator.stop()
            }
        )
        shortcutController?.install()
    }

    func startListening() async {
        guard runState != .connecting, runState != .listening, runState != .stopping else {
            return
        }

        lastError = nil
        overlayState.resetSession()
        sessionID = UUID()
        sessionGeneration = UUID()

        switch mode {
        case .localMock:
            startLocalMock()
        case .backend:
            await startBackendMicrophone()
        }
    }

    func stopListening() async {
        mockTask?.cancel()
        mockTask = nil
        await stopBackendResources(sendStop: true)
        if runState != .failed {
            runState = .idle
        }
        microphoneState = .stopped
    }

    func shutdown() async {
        await stopListening()
    }

    private func startLocalMock() {
        mockTask?.cancel()
        runState = .listening
        microphoneState = .idle

        mockTask = Task { [weak self] in
            let source = MockOverlayEventSource()
            for await event in source.events() {
                if Task.isCancelled { return }
                self?.handleServerMessage(event)
            }
            self?.finishLocalMock()
        }
    }

    private func finishLocalMock() {
        if runState == .listening {
            runState = .connected
        }
    }

    private func startBackendMicrophone() async {
        guard let url = URL(string: backendURLString),
              url.scheme == "ws" || url.scheme == "wss" else {
            fail("Backend WebSocket URL must start with ws:// or wss://.")
            return
        }

        runState = .connecting
        microphoneState = .requestingPermission

        let client = BackendWebSocketClient(url: url)
        let generation = sessionGeneration
        let coordinator = AudioStreamCoordinator(
            detector: EnergySpeechEndpointDetector(),
            websocket: client
        )
        let microphone = MicrophoneAudioCaptureService()
        backendClient = client
        audioCoordinator = coordinator
        microphoneService = microphone

        do {
            try await client.connect()
            startReceiveLoop(client: client, generation: generation)
            try await coordinator.start(sessionID: sessionID, source: .microphone)

            let pipe = BoundedAudioChunkPipe(limit: 48) { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.handleAudioPipelineOverflow(generation: generation)
                }
            }
            audioPipe = pipe
            audioProcessingTask = Task { [weak self, coordinator] in
                do {
                    for await chunk in pipe.stream {
                        try Task.checkCancellation()
                        guard self?.sessionGeneration == generation else { return }
                        try await coordinator.process(chunk)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self?.handleAudioProcessingError(error)
                }
            }

            try await microphone.start { chunk in
                pipe.yield(chunk)
            }
            runState = .listening
            microphoneState = .listening
        } catch {
            await stopBackendResources(sendStop: false)
            if let captureError = error as? AudioCaptureError,
               captureError == .microphonePermissionDenied {
                microphoneState = .stopped
            } else {
                microphoneState = .interrupted
            }
            fail(userFacingMessage(for: error))
        }
    }

    private func startReceiveLoop(client: BackendWebSocketClient, generation: UUID) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, client] in
            let stream = await client.receiveMessages()
            do {
                for try await message in stream {
                    guard self?.sessionGeneration == generation else { return }
                    self?.handleServerMessage(message)
                }
            } catch is CancellationError {
                return
            } catch {
                guard self?.sessionGeneration == generation else { return }
                self?.handleUnexpectedDisconnect(error)
            }
        }
    }

    private func handleServerMessage(_ message: ServerMessage) {
        overlayState.apply(message)

        switch message {
        case let .sessionState(session):
            if session.status == .ready || session.status == .connected {
                if runState == .connecting {
                    runState = .connected
                }
            } else if session.status == .closed {
                runState = .idle
            }

        case let .recoverableError(error):
            lastError = error.message

        case let .fatalError(error):
            lastError = error.message
            runState = .failed
            Task { [weak self] in
                await self?.stopBackendResources(sendStop: false)
            }

        case .transcriptDelta, .transcriptCompleted, .overlayResult:
            break
        }
    }

    private func handleUnexpectedDisconnect(_ error: Error) {
        guard runState != .idle, runState != .stopping else { return }
        microphoneState = .interrupted
        fail(userFacingMessage(for: error))
        Task { [weak self] in
            await self?.stopBackendResources(sendStop: false)
        }
    }

    private func handleAudioProcessingError(_ error: Error) {
        microphoneState = .interrupted
        fail(userFacingMessage(for: error))
        Task { [weak self] in
            await self?.stopBackendResources(sendStop: false)
        }
    }

    private func stopBackendResources(sendStop: Bool) async {
        if isCleaningUp {
            return
        }
        isCleaningUp = true
        defer { isCleaningUp = false }

        if runState != .idle && runState != .failed {
            runState = .stopping
        }

        microphoneService?.stop()
        microphoneService = nil
        audioPipe?.finish()
        audioPipe = nil
        audioProcessingTask?.cancel()
        audioProcessingTask = nil

        var cleanupError: Error?
        if sendStop, let audioCoordinator {
            do {
                try await audioCoordinator.stop(source: .microphone)
            } catch {
                cleanupError = error
            }
        } else if let backendClient {
            if let audioCoordinator {
                try? await audioCoordinator.cancelActiveUtterance(reason: .captureInterrupted)
            }
            await backendClient.disconnect()
        }

        receiveTask?.cancel()
        receiveTask = nil
        audioCoordinator = nil
        backendClient = nil

        if let cleanupError, lastError == nil {
            lastError = userFacingMessage(for: cleanupError)
        }
    }

    private func handleAudioPipelineOverflow(generation: UUID) async {
        guard sessionGeneration == generation else { return }
        microphoneState = .interrupted
        lastError = "Audio pipeline overflow interrupted the current microphone session."
        overlayState.apply(.recoverableError(RecoverableErrorMessage(
            code: "audio_pipeline_overflow",
            message: "Audio pipeline overflow interrupted the current microphone session."
        )))
        if let audioCoordinator {
            try? await audioCoordinator.cancelActiveUtterance(reason: .audioPipelineOverflow)
        }
        await stopBackendResources(sendStop: true)
        runState = .failed
    }

    private func fail(_ message: String) {
        lastError = message
        runState = .failed
        overlayState.apply(.recoverableError(RecoverableErrorMessage(
            code: "app_error",
            message: message
        )))
    }

    private func userFacingMessage(for error: Error) -> String {
        if let captureError = error as? AudioCaptureError {
            switch captureError {
            case .microphonePermissionDenied:
                return "Microphone permission was denied."
            case .screenRecordingPermissionDenied:
                return "Screen/audio capture permission is unavailable."
            case .deviceUnavailable:
                return "The selected audio device is unavailable."
            case .systemAudioUnavailable:
                return "System audio capture is not available in the P0 microphone build."
            }
        }

        if let clientError = error as? BackendWebSocketClient.ClientError {
            switch clientError {
            case .notConnected:
                return "Backend WebSocket is not connected."
            case .invalidServerPayload:
                return "Backend sent a malformed message."
            case .alreadyReceiving:
                return "A backend receive loop is already active."
            case .alreadyConnecting:
                return "Backend connection is already in progress."
            case .cancelled:
                return "Backend connection was cancelled."
            }
        }

        return "LiveOverlayTranslator encountered a recoverable error."
    }
}
