import Foundation

public struct AudioChunk: Sendable {
    public let source: AudioSource
    public let pcmSamples: [Int16]
    public let timestampMs: Int

    public init(source: AudioSource, pcmSamples: [Int16], timestampMs: Int) {
        self.source = source
        self.pcmSamples = pcmSamples
        self.timestampMs = timestampMs
    }
}

public protocol AudioCaptureService: AnyObject {
    var source: AudioSource { get }
    func start(onChunk: @escaping @Sendable (AudioChunk) -> Void) async throws
    func stop()
}

public enum AudioCaptureError: Error, Equatable {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case deviceUnavailable
}
