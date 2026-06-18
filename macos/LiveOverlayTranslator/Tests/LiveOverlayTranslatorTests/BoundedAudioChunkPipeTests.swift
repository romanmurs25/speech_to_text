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
    let pipe = BoundedAudioChunkPipe(limit: 1) {
        overflowCount.increment()
    }

    pipe.yield(AudioChunk(source: .microphone, pcmSamples: [1], timestampMs: 0))
    pipe.yield(AudioChunk(source: .microphone, pcmSamples: [2], timestampMs: 1))
    pipe.yield(AudioChunk(source: .microphone, pcmSamples: [3], timestampMs: 2))

    #expect(overflowCount.value == 1)
}

@Test
func boundedAudioChunkPipeIgnoresYieldAfterFinish() {
    let overflowCount = OverflowCounter()
    let pipe = BoundedAudioChunkPipe(limit: 1) {
        overflowCount.increment()
    }

    pipe.finish()
    pipe.yield(AudioChunk(source: .microphone, pcmSamples: [1], timestampMs: 0))

    #expect(overflowCount.value == 0)
}
