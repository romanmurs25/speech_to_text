import Foundation

public enum WebSocketTransportMessage: Equatable, Sendable {
    case string(String)
    case data(Data)
}

public protocol WebSocketTransport: Sendable {
    func connect(to url: URL) async throws
    func disconnect() async
    func sendString(_ text: String) async throws
    func sendData(_ data: Data) async throws
    func receive() async throws -> WebSocketTransportMessage
}

public final class URLSessionWebSocketTransport: NSObject, URLSessionWebSocketDelegate, WebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var openContinuation: CheckedContinuation<Void, Error>?

    public override init() {
        super.init()
    }

    public func connect(to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            openContinuation = continuation
            lock.unlock()

            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.webSocketTask(with: url)

            lock.lock()
            self.session = session
            self.task = task
            lock.unlock()

            task.resume()
        }
    }

    public func disconnect() async {
        let (task, session, continuation) = takeConnectionForDisconnect()
        continuation?.resume(throwing: BackendWebSocketClient.ClientError.cancelled)
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    public func sendString(_ text: String) async throws {
        guard let task = currentTask() else { throw BackendWebSocketClient.ClientError.notConnected }
        try await task.send(.string(text))
    }

    public func sendData(_ data: Data) async throws {
        guard let task = currentTask() else { throw BackendWebSocketClient.ClientError.notConnected }
        try await task.send(.data(data))
    }

    public func receive() async throws -> WebSocketTransportMessage {
        guard let task = currentTask() else { throw BackendWebSocketClient.ClientError.notConnected }
        switch try await task.receive() {
        case let .string(text):
            return .string(text)
        case let .data(data):
            return .data(data)
        @unknown default:
            throw BackendWebSocketClient.ClientError.invalidServerPayload
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        resumeOpenContinuation(with: .success(()))
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resumeOpenContinuation(with: .failure(error))
        }
    }

    private func currentTask() -> URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    private func takeConnectionForDisconnect() -> (
        URLSessionWebSocketTask?,
        URLSession?,
        CheckedContinuation<Void, Error>?
    ) {
        lock.lock()
        defer { lock.unlock() }
        let task = task
        let session = session
        self.task = nil
        self.session = nil
        let continuation = openContinuation
        openContinuation = nil
        return (task, session, continuation)
    }

    private func resumeOpenContinuation(with result: Result<Void, Error>) {
        lock.lock()
        let continuation = openContinuation
        openContinuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation?.resume()
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}

public actor BackendWebSocketClient {
    public enum ClientError: Error {
        case notConnected
        case invalidServerPayload
        case alreadyReceiving
        case alreadyConnecting
        case cancelled
    }

    private let url: URL
    private let transport: WebSocketTransport
    private var isConnected = false
    private var isConnecting = false
    private var isDisconnecting = false
    private var isReceiving = false

    public init(url: URL, transport: WebSocketTransport = URLSessionWebSocketTransport()) {
        self.url = url
        self.transport = transport
    }

    public func connect() async throws {
        if isConnected {
            return
        }
        if isConnecting {
            throw ClientError.alreadyConnecting
        }

        isConnecting = true
        isDisconnecting = false
        do {
            try await transport.connect(to: url)
            isConnected = true
            isConnecting = false
        } catch {
            isConnected = false
            isConnecting = false
            throw error
        }
    }

    public func disconnect() async {
        isConnecting = false
        isDisconnecting = true
        isConnected = false
        isReceiving = false
        await transport.disconnect()
    }

    public func send(_ message: ClientControlMessage) async throws {
        guard isConnected else { throw ClientError.notConnected }
        let data = try JSONEncoder.protocolEncoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClientError.invalidServerPayload
        }
        try await transport.sendString(text)
    }

    public func sendAudio(_ pcm: Data) async throws {
        guard isConnected else { throw ClientError.notConnected }
        try await transport.sendData(pcm)
    }

    public func receiveMessages() -> AsyncThrowingStream<ServerMessage, Error> {
        guard !isReceiving else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ClientError.alreadyReceiving)
            }
        }

        isReceiving = true
        let transport = self.transport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await transport.receive()
                        switch message {
                        case let .string(text):
                            guard let data = text.data(using: .utf8) else {
                                throw ClientError.invalidServerPayload
                            }
                            continuation.yield(try JSONDecoder.protocolDecoder.decode(ServerMessage.self, from: data))
                        case let .data(data):
                            guard let text = String(data: data, encoding: .utf8),
                                  let textData = text.data(using: .utf8) else {
                                throw ClientError.invalidServerPayload
                            }
                            continuation.yield(try JSONDecoder.protocolDecoder.decode(ServerMessage.self, from: textData))
                        @unknown default:
                            throw ClientError.invalidServerPayload
                        }
                    }
                } catch {
                    if self.isUserDisconnecting() || Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
                self.finishReceiveLoop()
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await self.finishReceiveLoop()
                }
            }
        }
    }

    private func isUserDisconnecting() -> Bool {
        isDisconnecting
    }

    private func finishReceiveLoop() {
        isReceiving = false
    }
}
