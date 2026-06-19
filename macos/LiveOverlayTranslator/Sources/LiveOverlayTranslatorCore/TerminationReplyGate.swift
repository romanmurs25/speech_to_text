public enum TerminationReplyReason: Equatable, Sendable {
    case cleanupFinished
    case timeout
}

public actor TerminationReplyGate {
    private var didReply = false
    private var storedReason: TerminationReplyReason?

    public init() {}

    public var replyReason: TerminationReplyReason? {
        storedReason
    }

    public func replyIfNeeded(reason: TerminationReplyReason) -> Bool {
        guard !didReply else {
            return false
        }
        didReply = true
        storedReason = reason
        return true
    }
}
