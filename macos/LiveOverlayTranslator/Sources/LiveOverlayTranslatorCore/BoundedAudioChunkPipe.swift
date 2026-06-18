import Foundation

public enum AudioChunkPipeYieldResult: Equatable, Sendable {
    case enqueued
    case overflowed
    case terminated
}

public final class BoundedAudioChunkPipe: @unchecked Sendable {
    public let stream: AsyncStream<AudioChunk>

    private let lock = NSLock()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var didNotifyOverflow = false
    private var isFinished = false
    private let invalidationToken: SessionInvalidationToken?
    private let onOverflow: @Sendable () -> Void

    public init(
        limit: Int,
        invalidationToken: SessionInvalidationToken? = nil,
        onOverflow: @escaping @Sendable () -> Void
    ) {
        self.invalidationToken = invalidationToken
        self.onOverflow = onOverflow
        var capturedContinuation: AsyncStream<AudioChunk>.Continuation?
        self.stream = AsyncStream<AudioChunk>(bufferingPolicy: .bufferingNewest(limit)) {
            capturedContinuation = $0
        }
        self.continuation = capturedContinuation
    }

    @discardableResult
    public func yield(_ chunk: AudioChunk) -> AudioChunkPipeYieldResult {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return .terminated
        }
        let result = continuation.yield(chunk)

        switch result {
        case .enqueued:
            lock.unlock()
            return .enqueued
        case .dropped:
            let shouldNotify = invalidateLocked(reason: .audioPipelineOverflow)
            lock.unlock()
            if shouldNotify {
                onOverflow()
            }
            return .overflowed
        case .terminated:
            isFinished = true
            self.continuation = nil
            lock.unlock()
            return .terminated
        @unknown default:
            lock.unlock()
            return .terminated
        }
    }

    public func finish() {
        lock.lock()
        let continuation = self.continuation
        isFinished = true
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }

    public func invalidate(reason: SessionInvalidationReason) {
        lock.lock()
        _ = invalidateLocked(reason: reason)
        lock.unlock()
    }

    private func invalidateLocked(reason: SessionInvalidationReason) -> Bool {
        invalidationToken?.invalidate(reason: reason)
        let continuation = continuation
        isFinished = true
        self.continuation = nil
        continuation?.finish()

        if reason == .audioPipelineOverflow && !didNotifyOverflow {
            didNotifyOverflow = true
            return true
        }
        return false
    }
}
