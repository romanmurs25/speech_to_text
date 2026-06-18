import Testing
@testable import LiveOverlayTranslatorCore

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

    guard case let .started(preRollSamples) = startEvents.first else {
        Issue.record("Expected speech start event")
        return
    }
    #expect(preRollSamples.count >= 300)

    guard case let .ended(utterance) = endEvents.first else {
        Issue.record("Expected speech end event")
        return
    }
    #expect(utterance.startedAtMs == 0)
    #expect(utterance.endedAtMs == 640)
    #expect(utterance.samples.count >= 420)
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
        if case .ended = event { return true }
        return false
    })
}
