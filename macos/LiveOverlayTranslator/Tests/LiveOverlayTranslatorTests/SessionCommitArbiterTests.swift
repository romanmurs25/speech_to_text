import Testing
@testable import LiveOverlayTranslatorCore

@Test
func sessionCommitArbiterDeniesCommitAfterOverflowInvalidation() {
    let arbiter = SessionCommitArbiter()

    #expect(arbiter.invalidate(reason: .audioPipelineOverflow) == .invalidated)
    #expect(!arbiter.tryAdmitCommit())
    #expect(arbiter.snapshot == .invalidated(reason: .audioPipelineOverflow))
}

@Test
func sessionCommitArbiterAllowsOneCommitAdmissionBeforeLaterInvalidation() {
    let arbiter = SessionCommitArbiter()

    #expect(arbiter.tryAdmitCommit())
    #expect(!arbiter.tryAdmitCommit())
    #expect(arbiter.invalidate(reason: .audioPipelineOverflow) == .commitAlreadyAdmitted)
    #expect(arbiter.snapshot == .commitAdmittedThenInvalidated(reason: .audioPipelineOverflow))
}

@Test
func sessionCommitArbiterTracksSendBoundaryAndFinish() {
    let arbiter = SessionCommitArbiter()

    #expect(arbiter.tryAdmitCommit())
    #expect(arbiter.markCommitSendStarted() == .started)
    #expect(arbiter.markCommitSendCompleted() == .completed)
    #expect(arbiter.finish() == .finished)
    #expect(arbiter.snapshot == .finished)
}
