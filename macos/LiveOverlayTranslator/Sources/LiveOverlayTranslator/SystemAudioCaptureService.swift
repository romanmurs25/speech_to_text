import Foundation
import LiveOverlayTranslatorCore

#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

final class SystemAudioCaptureService: AudioCaptureService {
    let source: AudioSource = .systemAudio
    private var onChunk: (@Sendable (AudioChunk) -> Void)?

    func start(onChunk: @escaping @Sendable (AudioChunk) -> Void) async throws {
        self.onChunk = onChunk
        #if canImport(ScreenCaptureKit)
        _ = try await SCShareableContent.current
        #else
        throw AudioCaptureError.screenRecordingPermissionDenied
        #endif
    }

    func stop() {
        onChunk = nil
    }
}
