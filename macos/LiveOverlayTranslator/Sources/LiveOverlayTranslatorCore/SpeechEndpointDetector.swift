import Foundation

public struct SpeechEndpointSettings: Equatable, Sendable {
    public var sampleRate: Int = 24_000
    public var preRollMs: Int = 300
    public var speechStartConfirmationMs: Int = 120
    public var phraseEndingSilenceMs: Int = 650
    public var maximumUtteranceDurationMs: Int = 20_000
    public var minimumNonSilentUtteranceMs: Int = 250
    public var initialNoiseFloor: Double = 120
    public var speechEnergyMultiplier: Double = 3
    public var noiseAdaptation: Double = 0.05

    public init() {}
}

public struct DetectedUtterance: Equatable, Sendable {
    public let samples: [Int16]
    public let startedAtMs: Int
    public let endedAtMs: Int
}

public enum SpeechEndpointEvent: Equatable, Sendable {
    case speechStarted(startedAtMs: Int, initialSamples: [Int16])
    case speechSamples([Int16])
    case speechEnded(endedAtMs: Int)
    case utteranceDiscarded(reason: String)
}

public protocol SpeechEndpointDetector {
    func process(samples: [Int16], timestampMs: Int) -> [SpeechEndpointEvent]
    func reset()
}

public final class EnergySpeechEndpointDetector: SpeechEndpointDetector {
    private enum State {
        case idle
        case speech
    }

    private let settings: SpeechEndpointSettings
    private var state: State = .idle
    private var noiseFloor: Double
    private var preRoll: [Int16] = []
    private var pendingSpeech: [Int16] = []
    private var speechStartCandidateMs: Int?
    private var utteranceStartedAtMs: Int?
    private var silenceStartedAtMs: Int?
    private var nonSilentSamples = 0

    public init(settings: SpeechEndpointSettings = SpeechEndpointSettings()) {
        self.settings = settings
        self.noiseFloor = settings.initialNoiseFloor
    }

    public func process(samples: [Int16], timestampMs: Int) -> [SpeechEndpointEvent] {
        guard !samples.isEmpty else { return [] }

        let chunkEnergy = averageEnergy(samples)
        let chunkDurationMs = durationMs(forSampleCount: samples.count)
        let chunkEndMs = timestampMs + chunkDurationMs
        let threshold = max(noiseFloor * settings.speechEnergyMultiplier, noiseFloor + 1)
        let isSpeech = chunkEnergy >= threshold
        var events: [SpeechEndpointEvent] = []

        if !isSpeech {
            adaptNoiseFloor(with: chunkEnergy)
            appendPreRoll(samples)
        }

        switch state {
        case .idle:
            if isSpeech {
                if speechStartCandidateMs == nil {
                    speechStartCandidateMs = timestampMs
                }
                pendingSpeech.append(contentsOf: samples)
                nonSilentSamples += samples.count
                if durationMs(forSampleCount: pendingSpeech.count) >= settings.speechStartConfirmationMs {
                    let start = max(0, (speechStartCandidateMs ?? timestampMs) - durationMs(forSampleCount: preRoll.count))
                    utteranceStartedAtMs = start
                    events.append(.speechStarted(startedAtMs: start, initialSamples: preRoll + pendingSpeech))
                    preRoll.removeAll(keepingCapacity: true)
                    pendingSpeech.removeAll(keepingCapacity: true)
                    state = .speech
                }
            } else {
                speechStartCandidateMs = nil
                pendingSpeech.removeAll(keepingCapacity: true)
                nonSilentSamples = 0
            }

        case .speech:
            events.append(.speechSamples(samples))
            if isSpeech {
                silenceStartedAtMs = nil
                nonSilentSamples += samples.count
            } else {
                if silenceStartedAtMs == nil {
                    silenceStartedAtMs = timestampMs
                }
            }

            let silenceDuration = chunkEndMs - (silenceStartedAtMs ?? chunkEndMs)
            let utteranceDuration = chunkEndMs - (utteranceStartedAtMs ?? timestampMs)
            if silenceDuration >= settings.phraseEndingSilenceMs ||
                utteranceDuration >= settings.maximumUtteranceDurationMs {
                if durationMs(forSampleCount: nonSilentSamples) >= settings.minimumNonSilentUtteranceMs {
                    events.append(.speechEnded(endedAtMs: chunkEndMs))
                } else {
                    events.append(.utteranceDiscarded(reason: "minimum_speech_duration_not_met"))
                }
                resetAfterUtterance(trailingPreRoll: isSpeech ? [] : samples)
            }
        }

        return events
    }

    public func reset() {
        state = .idle
        preRoll.removeAll(keepingCapacity: true)
        pendingSpeech.removeAll(keepingCapacity: true)
        speechStartCandidateMs = nil
        utteranceStartedAtMs = nil
        silenceStartedAtMs = nil
        nonSilentSamples = 0
        noiseFloor = settings.initialNoiseFloor
    }

    private func resetAfterUtterance(trailingPreRoll: [Int16] = []) {
        state = .idle
        pendingSpeech.removeAll(keepingCapacity: true)
        speechStartCandidateMs = nil
        utteranceStartedAtMs = nil
        silenceStartedAtMs = nil
        nonSilentSamples = 0
        preRoll.removeAll(keepingCapacity: true)
        appendPreRoll(trailingPreRoll)
    }

    private func appendPreRoll(_ samples: [Int16]) {
        preRoll.append(contentsOf: samples)
        let maxSamples = settings.sampleRate * settings.preRollMs / 1_000
        if preRoll.count > maxSamples {
            preRoll.removeFirst(preRoll.count - maxSamples)
        }
    }

    private func durationMs(forSampleCount count: Int) -> Int {
        count * 1_000 / max(settings.sampleRate, 1)
    }

    private func averageEnergy(_ samples: [Int16]) -> Double {
        let total = samples.reduce(0.0) { partial, sample in
            partial + Double(abs(Int(sample)))
        }
        return total / Double(samples.count)
    }

    private func adaptNoiseFloor(with energy: Double) {
        noiseFloor = noiseFloor * (1 - settings.noiseAdaptation) + energy * settings.noiseAdaptation
    }
}
