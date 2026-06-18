import Foundation

public enum SessionInvalidationReason: String, Equatable, Sendable {
    case userStop
    case audioPipelineOverflow
    case backendDisconnected
    case terminalServerError
    case captureInterrupted
    case applicationShutdown
    case staleGeneration

    public var utteranceCancelReason: UtteranceCancelReason {
        switch self {
        case .userStop:
            return .userInterrupted
        case .audioPipelineOverflow:
            return .audioPipelineOverflow
        case .applicationShutdown:
            return .applicationShutdown
        case .backendDisconnected, .terminalServerError, .captureInterrupted, .staleGeneration:
            return .captureInterrupted
        }
    }
}

public final class SessionInvalidationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: SessionInvalidationReason?

    public init() {}

    @discardableResult
    public func invalidate(reason: SessionInvalidationReason) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if self.reason != nil {
            return false
        }
        self.reason = reason
        return true
    }

    public var isInvalidated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reason != nil
    }

    public var invalidationReason: SessionInvalidationReason? {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }
}
