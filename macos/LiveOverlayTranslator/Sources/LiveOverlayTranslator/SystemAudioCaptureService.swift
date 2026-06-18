import Foundation
import LiveOverlayTranslatorCore

final class SystemAudioCaptureService: AudioCaptureService, @unchecked Sendable {
    let source: AudioSource = .systemAudio

    func start(onChunk _: @escaping @Sendable (AudioChunk) -> Void) async throws {
        throw AudioCaptureError.systemAudioUnavailable
    }

    func stop() {
    }
}
