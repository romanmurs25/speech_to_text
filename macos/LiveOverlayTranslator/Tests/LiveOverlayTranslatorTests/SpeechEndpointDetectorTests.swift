import Testing
@testable import LiveOverlayTranslatorCore

@Test
func pcmFrameChunkerEmitsLittleEndianBoundedFrames() {
    var settings = AudioStreamSettings()
    settings.sampleRate = 1_000
    settings.frameDurationMs = 100
    settings.maxFrameBytes = 8
    let chunker = PCMFrameChunker(settings: settings)

    let frames = chunker.frames(from: [1, 256, -2, 3, 4])

    #expect(frames.count == 2)
    #expect(frames.allSatisfy { $0.count <= 8 })
    #expect(Array(frames[0]) == [1, 0, 0, 1, 254, 255, 3, 0])
    #expect(Array(frames[1]) == [4, 0])
}

@Test
func energyDetectorPreservesPreRollAndEndsAfterSilence() {
    var settings = SpeechEndpointSettings()
    settings.sampleRate = 1_000
    settings.preRollMs = 300
    settings.speechStartConfirmationMs = 120
    settings.phraseEndingSilenceMs = 200
    settings.minimumNonSilentUtteranceMs = 100
    settings.initialNoiseFloor = 20
    settings.speechEnergyMultiplier = 3
    let detector = EnergySpeechEndpointDetector(settings: settings)

    _ = detector.process(samples: Array(repeating: 0, count: 300), timestampMs: 0)
    let startEvents = detector.process(samples: Array(repeating: 1_000, count: 120), timestampMs: 300)
    let endEvents = detector.process(samples: Array(repeating: 0, count: 220), timestampMs: 420)

    guard case let .speechStarted(startedAtMs, initialSamples) = startEvents.first else {
        Issue.record("Expected speech start event")
        return
    }
    #expect(startedAtMs == 0)
    #expect(initialSamples.count >= 420)

    #expect(endEvents.contains { event in
        if case .speechSamples = event { return true }
        return false
    })
    guard case let .speechEnded(endedAtMs) = endEvents.last else {
        Issue.record("Expected speech end event")
        return
    }
    #expect(endedAtMs == 640)
}

@Test
func energyDetectorIgnoresEffectivelySilentUtterances() {
    var settings = SpeechEndpointSettings()
    settings.sampleRate = 1_000
    settings.preRollMs = 100
    settings.speechStartConfirmationMs = 50
    settings.phraseEndingSilenceMs = 50
    settings.minimumNonSilentUtteranceMs = 250
    settings.initialNoiseFloor = 20
    settings.speechEnergyMultiplier = 3
    let detector = EnergySpeechEndpointDetector(settings: settings)

    _ = detector.process(samples: Array(repeating: 1_000, count: 60), timestampMs: 0)
    let events = detector.process(samples: Array(repeating: 0, count: 60), timestampMs: 60)

    #expect(!events.contains { event in
        if case .speechEnded = event { return true }
        return false
    })
}

@Test
func energyDetectorEndsContinuousSpeechAtMaximumDuration() {
    var settings = SpeechEndpointSettings()
    settings.sampleRate = 1_000
    settings.preRollMs = 100
    settings.speechStartConfirmationMs = 50
    settings.phraseEndingSilenceMs = 500
    settings.maximumUtteranceDurationMs = 200
    settings.minimumNonSilentUtteranceMs = 50
    settings.initialNoiseFloor = 20
    settings.speechEnergyMultiplier = 3
    let detector = EnergySpeechEndpointDetector(settings: settings)

    _ = detector.process(samples: Array(repeating: 1_000, count: 50), timestampMs: 0)
    _ = detector.process(samples: Array(repeating: 1_000, count: 50), timestampMs: 50)
    _ = detector.process(samples: Array(repeating: 1_000, count: 50), timestampMs: 100)
    let events = detector.process(samples: Array(repeating: 1_000, count: 50), timestampMs: 150)

    #expect(events.contains { event in
        if case let .speechEnded(endedAtMs) = event {
            return endedAtMs == 200
        }
        return false
    })
}

@Test
func energyDetectorPreservesBoundedPreRollForSecondUtterance() {
    var settings = SpeechEndpointSettings()
    settings.sampleRate = 1_000
    settings.preRollMs = 100
    settings.speechStartConfirmationMs = 50
    settings.phraseEndingSilenceMs = 100
    settings.minimumNonSilentUtteranceMs = 50
    settings.initialNoiseFloor = 20
    settings.speechEnergyMultiplier = 3
    let detector = EnergySpeechEndpointDetector(settings: settings)

    _ = detector.process(samples: Array(repeating: 0, count: 100), timestampMs: 0)
    _ = detector.process(samples: Array(repeating: 1_000, count: 50), timestampMs: 100)
    _ = detector.process(samples: Array(repeating: 0, count: 100), timestampMs: 150)
    let secondStart = detector.process(samples: Array(repeating: 1_000, count: 50), timestampMs: 250)

    guard case let .speechStarted(startedAtMs, initialSamples) = secondStart.first else {
        Issue.record("Expected second speech start")
        return
    }
    #expect(startedAtMs == 150)
    #expect(initialSamples.count == 150)
}
