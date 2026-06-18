import Foundation

public protocol PCMResampler {
    func convertFloat32ToPCM16Mono24kHz(samples: [Float], inputSampleRate: Int, channels: Int) -> [Int16]
}

public struct SimplePCMResampler: PCMResampler, Sendable {
    public init() {}

    public func convertFloat32ToPCM16Mono24kHz(samples: [Float], inputSampleRate: Int, channels: Int) -> [Int16] {
        guard channels > 0, inputSampleRate > 0 else { return [] }
        let frameCount = samples.count / channels
        guard frameCount > 0 else { return [] }

        var mono: [Float] = []
        mono.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += samples[frame * channels + channel]
            }
            mono.append(sum / Float(channels))
        }

        if inputSampleRate == 24_000 {
            return mono.map(Self.floatToInt16)
        }

        let outputCount = max(1, mono.count * 24_000 / inputSampleRate)
        return (0..<outputCount).map { index in
            let sourceIndex = min(mono.count - 1, index * inputSampleRate / 24_000)
            return Self.floatToInt16(mono[sourceIndex])
        }
    }

    private static func floatToInt16(_ value: Float) -> Int16 {
        let clamped = min(1, max(-1, value))
        return Int16(clamped * Float(Int16.max))
    }
}
