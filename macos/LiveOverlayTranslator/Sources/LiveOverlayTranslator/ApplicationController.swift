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
    case connectingBackend
    case waitingForMicrophonePermission
    case startingCapture
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

private enum SessionCleanupOutcome {
    case userStop
    case terminalFailure(String)
    case overflow
    case startupCancellation
    case captureInterrupted(String)
    case applicationShutdown

    var invalidationReason: SessionInvalidationReason {
        switch self {
        case .userStop:
            return .userStop
        case .terminalFailure:
            return .terminalServerError
        case .overflow:
            return .audioPipelineOverflow
        case .startupCancellation:
            return .staleGeneration
        case .captureInterrupted:
            return .captureInterrupted
        case .applicationShutdown:
            return .applicationShutdown
        }
    }

    var isFailure: Bool {
        switch self {
        case .terminalFailure, .overflow, .captureInterrupted:
            return true
        case .userStop, .startupCancellation, .applicationShutdown:
            return false
        }
    }
}

@MainActor
final class ApplicationController: ObservableObject {
    private final class LocalMockRunContext {
        let generation = UUID()
        let invalidationToken = SessionInvalidationToken()
        var task: Task<Void, Never>?
    }

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
    private var currentMock: LocalMockRunContext?
    private var currentSession: BackendMicrophoneSessionContext?

    var controlsLocked: Bool {
        switch runState {
        case .idle, .failed:
            return currentSession != nil
        case .connectingBackend, .waitingForMicrophonePermission, .startingCapture, .listening, .stopping:
            return true
        }
    }

    var canStartListening: Bool {
        currentSession == nil && currentMock == nil && (runState == .idle || runState == .failed)
    }

    var canStopListening: Bool {
        switch runState {
        case .connectingBackend, .waitingForMicrophonePermission, .startingCapture, .listening:
            return true
        case .idle, .stopping, .failed:
            return false
        }
    }

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
        guard canStartListening else {
            return
        }

        lastError = nil
        overlayState.resetSession()

        switch mode {
        case .localMock:
            startLocalMock()
        case .backend:
            await startBackendMicrophone()
        }
    }

    func stopListening() async {
        if let mock = currentMock {
            mock.invalidationToken.invalidate(reason: .userStop)
            mock.task?.cancel()
            currentMock = nil
        }
        if let context = currentSession {
            await cleanup(context: context, outcome: .userStop, sendStop: true)
        } else {
            runState = .idle
            microphoneState = .stopped
        }
    }

    func shutdown() async {
        await stopListening()
    }

    func prepareForTermination() {
        if let mock = currentMock {
            mock.invalidationToken.invalidate(reason: .applicationShutdown)
            mock.task?.cancel()
            currentMock = nil
        }
        guard let context = currentSession else { return }
        context.invalidationToken.invalidate(reason: .applicationShutdown)
        context.microphone.stop()
        context.pipe.invalidate(reason: .applicationShutdown)
    }

    func shutdownForTermination() async {
        if let context = currentSession {
            await cleanup(context: context, outcome: .applicationShutdown, sendStop: false)
        }
    }

    private func startLocalMock() {
        currentMock?.task?.cancel()
        let context = LocalMockRunContext()
        currentMock = context
        runState = .listening
        microphoneState = .idle

        context.task = Task { [weak self, weak context] in
            let source = MockOverlayEventSource()
            for await event in source.events() {
                if Task.isCancelled { return }
                let shouldHandle = await MainActor.run {
                    guard let self, let context else {
                        return false
                    }
                    return self.isCurrent(context) && !context.invalidationToken.isInvalidated
                }
                guard shouldHandle else { return }
                await MainActor.run {
                    self?.handleServerMessage(event)
                }
            }
            await MainActor.run {
                guard let context else { return }
                self?.finishLocalMock(context: context)
            }
        }
    }

    private func finishLocalMock(context: LocalMockRunContext) {
        guard isCurrent(context), !context.invalidationToken.isInvalidated else {
            return
        }
        currentMock = nil
        if runState == .listening {
            runState = .idle
            microphoneState = .stopped
        }
    }

    private func startBackendMicrophone() async {
        guard let url = URL(string: backendURLString),
              url.scheme == "ws" || url.scheme == "wss" else {
            fail("Backend WebSocket URL must start with ws:// or wss://.")
            return
        }

        runState = .connectingBackend
        microphoneState = .idle

        let generation = UUID()
        let backendSessionID = UUID()
        let invalidationToken = SessionInvalidationToken()
        let client = BackendWebSocketClient(url: url)
        let coordinator = AudioStreamCoordinator(
            detector: EnergySpeechEndpointDetector(),
            websocket: client,
            invalidationToken: invalidationToken
        )
        let microphone = MicrophoneAudioCaptureService()
        let pipe = BoundedAudioChunkPipe(limit: 48, invalidationToken: invalidationToken) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleAudioPipelineOverflow(generation: generation)
            }
        }
        let context = BackendMicrophoneSessionContext(
            generation: generation,
            backendSessionID: backendSessionID,
            client: client,
            coordinator: coordinator,
            microphone: microphone,
            pipe: pipe,
            invalidationToken: invalidationToken
        )
        currentSession = context

        do {
            try await client.connect()
            guard await ensureCurrent(context) else {
                return
            }
            startReceiveLoop(context: context)
            try await coordinator.start(sessionID: backendSessionID, source: .microphone)
            guard await ensureCurrent(context) else {
                return
            }

            context.phase = .waitingForPermission
            runState = .waitingForMicrophonePermission
            microphoneState = .requestingPermission
            try await microphone.requestPermission()
            guard await ensureCurrent(context) else {
                return
            }

            context.phase = .startingCapture
            runState = .startingCapture
            context.audioProcessingTask = Task { [weak self, weak context, coordinator, pipe] in
                do {
                    for await chunk in pipe.stream {
                        try Task.checkCancellation()
                        guard let context else { return }
                        let isCurrent = await MainActor.run {
                            self?.isCurrent(context) == true && !context.invalidationToken.isInvalidated
                        }
                        guard isCurrent else { return }
                        try await coordinator.process(chunk)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await self?.handleAudioProcessingError(error, context: context)
                }
            }

            try microphone.startCapture { chunk in
                _ = pipe.yield(chunk)
            }
            context.microphoneCaptureStarted = true
            guard await ensureCurrent(context) else {
                microphone.stop()
                return
            }
            context.phase = .listening
            runState = .listening
            microphoneState = .listening
        } catch {
            let invalidationReason = context.invalidationToken.invalidationReason
            await cleanup(context: context, outcome: .captureInterrupted(userFacingMessage(for: error)), sendStop: false)
            if invalidationReason == .userStop ||
                invalidationReason == .staleGeneration ||
                invalidationReason == .applicationShutdown {
                return
            }
            if let captureError = error as? AudioCaptureError,
               captureError == .microphonePermissionDenied {
                microphoneState = .stopped
            } else {
                microphoneState = .interrupted
            }
            fail(userFacingMessage(for: error))
        }
    }

    private func startReceiveLoop(context: BackendMicrophoneSessionContext) {
        context.receiveTask?.cancel()
        context.receiveTask = Task { [weak self, weak context] in
            guard let context else { return }
            let client = context.client
            let stream = await client.receiveMessages()
            do {
                for try await message in stream {
                    let shouldHandle = await MainActor.run {
                        self?.isCurrent(context) == true && !context.invalidationToken.isInvalidated
                    }
                    guard shouldHandle else { return }
                    await MainActor.run {
                        self?.handleServerMessage(message, context: context)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                let shouldHandle = await MainActor.run {
                    self?.isCurrent(context) == true && !context.invalidationToken.isInvalidated
                }
                guard shouldHandle else { return }
                await self?.handleUnexpectedDisconnect(error, context: context)
            }
        }
    }

    private func handleServerMessage(_ message: ServerMessage, context: BackendMicrophoneSessionContext? = nil) {
        if let context, !isCurrent(context) {
            return
        }
        overlayState.apply(message)

        switch message {
        case let .sessionState(session):
            if session.status == .closed {
                if let context {
                    lastError = "Backend session closed."
                    Task { [weak self, weak context] in
                        guard let context else { return }
                        await self?.cleanup(
                            context: context,
                            outcome: .terminalFailure("Backend session closed."),
                            sendStop: false
                        )
                    }
                } else {
                    runState = .idle
                }
            }

        case let .recoverableError(error):
            lastError = error.message

        case let .fatalError(error):
            lastError = error.message
            runState = .failed
            if let context {
                Task { [weak self, weak context] in
                    guard let context else { return }
                    await self?.cleanup(context: context, outcome: .terminalFailure(error.message), sendStop: false)
                }
            }

        case .transcriptDelta, .transcriptCompleted, .overlayResult:
            break
        }
    }

    private func handleUnexpectedDisconnect(_ error: Error, context: BackendMicrophoneSessionContext) async {
        guard isCurrent(context) else { return }
        guard runState != .idle, runState != .stopping else { return }
        microphoneState = .interrupted
        fail(userFacingMessage(for: error))
        await cleanup(context: context, outcome: .captureInterrupted(userFacingMessage(for: error)), sendStop: false)
    }

    private func handleAudioProcessingError(_ error: Error, context: BackendMicrophoneSessionContext?) async {
        guard let context, isCurrent(context) else { return }
        microphoneState = .interrupted
        fail(userFacingMessage(for: error))
        await cleanup(context: context, outcome: .captureInterrupted(userFacingMessage(for: error)), sendStop: false)
    }

    private func cleanup(
        context: BackendMicrophoneSessionContext,
        outcome: SessionCleanupOutcome,
        sendStop: Bool
    ) async {
        if let cleanupTask = context.cleanupTask {
            await cleanupTask.value
            return
        }

        context.phase = .cleaningUp
        context.invalidationToken.invalidate(reason: outcome.invalidationReason)
        context.microphone.stop()
        context.pipe.invalidate(reason: outcome.invalidationReason)
        context.audioProcessingTask?.cancel()
        context.receiveTask?.cancel()

        if isCurrent(context), runState != .failed {
            runState = .stopping
        }

        let cleanupTask = Task { [context] in
            var cleanupError: Error?
            if sendStop {
                do {
                    try await context.coordinator.stop(source: .microphone)
                } catch {
                    cleanupError = error
                }
            } else {
                try? await context.coordinator.cancelActiveUtterance(reason: outcome.invalidationReason.utteranceCancelReason)
                await context.client.disconnect()
            }
            if cleanupError != nil {
                await context.client.disconnect()
            }
        }
        context.cleanupTask = cleanupTask
        await cleanupTask.value
        context.phase = .finished

        if isCurrent(context) {
            currentSession = nil
            if outcome.isFailure {
                runState = .failed
                microphoneState = .interrupted
                switch outcome {
                case let .terminalFailure(message), let .captureInterrupted(message):
                    lastError = message
                case .overflow:
                    lastError = "Audio pipeline overflow interrupted the current microphone session."
                case .userStop, .startupCancellation, .applicationShutdown:
                    break
                }
            } else {
                runState = .idle
                microphoneState = .stopped
            }
        }
    }

    private func handleAudioPipelineOverflow(generation: UUID) async {
        guard let context = currentSession, context.generation == generation else { return }
        microphoneState = .interrupted
        lastError = "Audio pipeline overflow interrupted the current microphone session."
        overlayState.apply(.recoverableError(RecoverableErrorMessage(
            code: "audio_pipeline_overflow",
            message: "Audio pipeline overflow interrupted the current microphone session."
        )))
        await cleanup(context: context, outcome: .overflow, sendStop: true)
    }

    private func ensureCurrent(_ context: BackendMicrophoneSessionContext) async -> Bool {
        guard isCurrent(context), !context.invalidationToken.isInvalidated else {
            await cleanup(context: context, outcome: .startupCancellation, sendStop: false)
            return false
        }
        return true
    }

    private func isCurrent(_ context: BackendMicrophoneSessionContext) -> Bool {
        currentSession === context && currentSession?.generation == context.generation
    }

    private func isCurrent(_ context: LocalMockRunContext) -> Bool {
        currentMock === context
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
