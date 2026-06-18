import Foundation

public final class BoundedAudioChunkPipe: @unchecked Sendable {
    public let stream: AsyncStream<AudioChunk>

    private let lock = NSLock()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var didNotifyOverflow = false
    private let onOverflow: @Sendable () -> Void

    public init(limit: Int, onOverflow: @escaping @Sendable () -> Void) {
        self.onOverflow = onOverflow
        var capturedContinuation: AsyncStream<AudioChunk>.Continuation?
        self.stream = AsyncStream<AudioChunk>(bufferingPolicy: .bufferingNewest(limit)) {
            capturedContinuation = $0
        }
        self.continuation = capturedContinuation
    }

    public func yield(_ chunk: AudioChunk) {
        guard let result = continuation?.yield(chunk) else {
            return
        }

        switch result {
        case .enqueued:
            return
        case .dropped:
            notifyOverflowOnce()
        case .terminated:
            return
        @unknown default:
            return
        }
    }

    public func finish() {
        continuation?.finish()
        continuation = nil
    }

    private func notifyOverflowOnce() {
        lock.lock()
        if didNotifyOverflow {
            lock.unlock()
            return
        }
        didNotifyOverflow = true
        lock.unlock()
        onOverflow()
    }
}
