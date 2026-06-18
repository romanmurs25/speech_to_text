import AVFoundation
import Foundation
import LiveOverlayTranslatorCore

final class MicrophoneAudioCaptureService: AudioCaptureService {
    let source: AudioSource = .microphone
    private let engine = AVAudioEngine()
    private let resampler: PCMResampler
    private var onChunk: (@Sendable (AudioChunk) -> Void)?

    init(resampler: PCMResampler = SimplePCMResampler()) {
        self.resampler = resampler
    }

    func start(onChunk: @escaping @Sendable (AudioChunk) -> Void) async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw AudioCaptureError.microphonePermissionDenied }
        self.onChunk = onChunk

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self,
                  let channelData = buffer.floatChannelData else { return }
            let channels = Int(format.channelCount)
            let frames = Int(buffer.frameLength)
            var interleaved: [Float] = []
            interleaved.reserveCapacity(frames * channels)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    interleaved.append(channelData[channel][frame])
                }
            }
            let pcm = self.resampler.convertFloat32ToPCM16Mono24kHz(
                samples: interleaved,
                inputSampleRate: Int(format.sampleRate),
                channels: channels
            )
            let timestampMs = Int(Date().timeIntervalSince1970 * 1_000)
            onChunk(AudioChunk(source: .microphone, pcmSamples: pcm, timestampMs: timestampMs))
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        onChunk = nil
    }
}
