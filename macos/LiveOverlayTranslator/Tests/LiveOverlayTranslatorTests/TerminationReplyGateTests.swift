import Testing
@testable import LiveOverlayTranslatorCore

@Test
func terminationReplyGateRepliesOnlyOnce() async {
    let gate = TerminationReplyGate()

    #expect(await gate.replyIfNeeded(reason: .cleanupFinished))
    #expect(!await gate.replyIfNeeded(reason: .timeout))
    #expect(await gate.replyReason == .cleanupFinished)
}

@Test
func terminationReplyGateLetsTimeoutWinWhenItArrivesFirst() async {
    let gate = TerminationReplyGate()

    #expect(await gate.replyIfNeeded(reason: .timeout))
    #expect(!await gate.replyIfNeeded(reason: .cleanupFinished))
    #expect(await gate.replyReason == .timeout)
}
