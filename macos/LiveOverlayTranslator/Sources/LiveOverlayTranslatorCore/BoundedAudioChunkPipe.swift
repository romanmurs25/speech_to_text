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
        lock.unlock()

        let result = continuation.yield(chunk)
        switch result {
        case .enqueued:
            return .enqueued
        case .dropped:
            let (continuationToFinish, shouldNotify) = takeForInvalidation(
                reason: .audioPipelineOverflow,
                notifyOverflow: true
            )
            continuationToFinish?.finish()
            if shouldNotify {
                onOverflow()
            }
            return .overflowed
        case .terminated:
            lock.lock()
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
        let (continuationToFinish, _) = takeForInvalidation(reason: reason, notifyOverflow: false)
        continuationToFinish?.finish()
    }

    private func takeForInvalidation(
        reason: SessionInvalidationReason,
        notifyOverflow: Bool
    ) -> (AsyncStream<AudioChunk>.Continuation?, Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return (nil, false)
        }

        invalidationToken?.invalidate(reason: reason)
        let continuation = continuation
        isFinished = true
        self.continuation = nil

        if notifyOverflow, reason == .audioPipelineOverflow, !didNotifyOverflow {
            didNotifyOverflow = true
            return (continuation, true)
        }
        return (continuation, false)
    }
}
