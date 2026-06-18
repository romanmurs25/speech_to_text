import Foundation

public actor BackendWebSocketClient {
    public enum ClientError: Error {
        case notConnected
        case invalidServerPayload
    }

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func connect() {
        task = session.webSocketTask(with: url)
        task?.resume()
    }

    public func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    public func send(_ message: ClientControlMessage) async throws {
        guard let task else { throw ClientError.notConnected }
        let data = try JSONEncoder.protocolEncoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClientError.invalidServerPayload
        }
        try await task.send(.string(text))
    }

    public func sendAudio(_ pcm: Data) async throws {
        guard let task else { throw ClientError.notConnected }
        try await task.send(.data(pcm))
    }

    public func receiveMessages() -> AsyncThrowingStream<ServerMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    while true {
                        guard let task else { throw ClientError.notConnected }
                        let message = try await task.receive()
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
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
