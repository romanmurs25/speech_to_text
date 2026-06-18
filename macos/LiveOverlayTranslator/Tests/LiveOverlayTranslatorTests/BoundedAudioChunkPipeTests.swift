import Foundation
import Testing
@testable import LiveOverlayTranslatorCore

private final class OverflowCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

@Test
func boundedAudioChunkPipeReportsOverflowOnce() {
    let overflowCount = OverflowCounter()
    let token = SessionInvalidationToken()
    let pipe = BoundedAudioChunkPipe(limit: 1, invalidationToken: token) {
        overflowCount.increment()
    }

    #expect(pipe.yield(AudioChunk(source: .microphone, pcmSamples: [1], timestampMs: 0)) == .enqueued)
    #expect(pipe.yield(AudioChunk(source: .microphone, pcmSamples: [2], timestampMs: 1)) == .overflowed)
    #expect(pipe.yield(AudioChunk(source: .microphone, pcmSamples: [3], timestampMs: 2)) == .terminated)

    #expect(overflowCount.value == 1)
    #expect(token.isInvalidated)
    #expect(token.invalidationReason == .audioPipelineOverflow)
}

@Test
func boundedAudioChunkPipeIgnoresYieldAfterFinish() {
    let overflowCount = OverflowCounter()
    let pipe = BoundedAudioChunkPipe(limit: 1) {
        overflowCount.increment()
    }

    pipe.finish()
    #expect(pipe.yield(AudioChunk(source: .microphone, pcmSamples: [1], timestampMs: 0)) == .terminated)

    #expect(overflowCount.value == 0)
}

@Test
func boundedAudioChunkPipeRejectsYieldAfterExplicitInvalidation() {
    let overflowCount = OverflowCounter()
    let token = SessionInvalidationToken()
    let pipe = BoundedAudioChunkPipe(limit: 2, invalidationToken: token) {
        overflowCount.increment()
    }

    pipe.invalidate(reason: .staleGeneration)

    #expect(pipe.yield(AudioChunk(source: .microphone, pcmSamples: [1], timestampMs: 0)) == .terminated)
    #expect(token.invalidationReason == .staleGeneration)
    #expect(overflowCount.value == 0)
}

@Test
func sessionInvalidationTokenKeepsFirstReason() {
    let token = SessionInvalidationToken()

    #expect(token.invalidate(reason: .userStop))
    #expect(!token.invalidate(reason: .audioPipelineOverflow))

    #expect(token.isInvalidated)
    #expect(token.invalidationReason == .userStop)
}

@Test
func boundedAudioChunkPipeYieldAndFinishAreThreadSafe() {
    let overflowCount = OverflowCounter()
    let pipe = BoundedAudioChunkPipe(limit: 8) {
        overflowCount.increment()
    }

    DispatchQueue.concurrentPerform(iterations: 20) { index in
        if index == 10 {
            pipe.finish()
        } else {
            _ = pipe.yield(AudioChunk(source: .microphone, pcmSamples: [Int16(index)], timestampMs: index))
        }
    }

    #expect(pipe.yield(AudioChunk(source: .microphone, pcmSamples: [1], timestampMs: 21)) == .terminated)
}
