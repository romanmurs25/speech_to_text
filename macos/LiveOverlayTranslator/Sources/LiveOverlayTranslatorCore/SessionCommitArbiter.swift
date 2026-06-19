import Foundation

public enum SessionCommitArbiterSnapshot: Equatable, Sendable {
    case open
    case invalidated(reason: SessionInvalidationReason)
    case commitAdmitted
    case commitSendStarted
    case commitSendCompleted
    case commitAdmittedThenInvalidated(reason: SessionInvalidationReason)
    case finished
}

public enum SessionCommitInvalidationOutcome: Equatable, Sendable {
    case invalidated
    case commitAlreadyAdmitted
    case alreadyInvalidated
    case finished
}

public enum SessionCommitSendStartOutcome: Equatable, Sendable {
    case started
    case denied
}

public enum SessionCommitSendCompletionOutcome: Equatable, Sendable {
    case completed
    case denied
}

public enum SessionCommitFinishOutcome: Equatable, Sendable {
    case finished
}

public final class SessionCommitArbiter: @unchecked Sendable {
    private let lock = NSLock()
    private var state: SessionCommitArbiterSnapshot = .open

    public init() {}

    public var snapshot: SessionCommitArbiterSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func tryAdmitCommit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .open else {
            return false
        }
        state = .commitAdmitted
        return true
    }

    @discardableResult
    public func invalidate(reason: SessionInvalidationReason) -> SessionCommitInvalidationOutcome {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .open:
            state = .invalidated(reason: reason)
            return .invalidated
        case .invalidated:
            return .alreadyInvalidated
        case .commitAdmitted, .commitSendStarted, .commitSendCompleted, .commitAdmittedThenInvalidated:
            state = .commitAdmittedThenInvalidated(reason: reason)
            return .commitAlreadyAdmitted
        case .finished:
            return .finished
        }
    }

    @discardableResult
    public func markCommitSendStarted() -> SessionCommitSendStartOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard state == .commitAdmitted else {
            return .denied
        }
        state = .commitSendStarted
        return .started
    }

    @discardableResult
    public func markCommitSendCompleted() -> SessionCommitSendCompletionOutcome {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .commitAdmitted, .commitSendStarted:
            state = .commitSendCompleted
            return .completed
        case .commitAdmittedThenInvalidated:
            return .completed
        case .open, .invalidated, .commitSendCompleted, .finished:
            return .denied
        }
    }

    @discardableResult
    public func finish() -> SessionCommitFinishOutcome {
        lock.lock()
        state = .finished
        lock.unlock()
        return .finished
    }
}
