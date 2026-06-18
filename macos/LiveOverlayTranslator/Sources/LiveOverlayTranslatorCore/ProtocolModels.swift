import Foundation

public enum AudioSource: String, Codable, Equatable, Sendable {
    case microphone
    case systemAudio
}

public enum Speaker: String, Codable, Equatable, Sendable {
    case local
    case remote
}

public struct HelloMessage: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let clientVersion: String
    public let sessionID: UUID

    public init(protocolVersion: Int, clientVersion: String, sessionID: UUID) {
        self.protocolVersion = protocolVersion
        self.clientVersion = clientVersion
        self.sessionID = sessionID
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case clientVersion = "client_version"
        case sessionID = "session_id"
    }
}

public struct StartStreamMessage: Codable, Equatable, Sendable {
    public let source: AudioSource
    public let sampleRate: Int
    public let channels: Int
    public let encoding: String
    public let languageHint: String?

    public init(
        source: AudioSource,
        sampleRate: Int = 24_000,
        channels: Int = 1,
        encoding: String = "pcm_s16le",
        languageHint: String? = nil
    ) {
        self.source = source
        self.sampleRate = sampleRate
        self.channels = channels
        self.encoding = encoding
        self.languageHint = languageHint
    }

    enum CodingKeys: String, CodingKey {
        case source
        case sampleRate = "sample_rate"
        case channels
        case encoding
        case languageHint = "language_hint"
    }
}

public struct UtteranceStartMessage: Codable, Equatable, Sendable {
    public let clientUtteranceID: String
    public let source: AudioSource
    public let speaker: Speaker
    public let sequence: Int
    public let startedAtMs: Int

    public init(
        clientUtteranceID: String,
        source: AudioSource,
        speaker: Speaker,
        sequence: Int,
        startedAtMs: Int
    ) {
        self.clientUtteranceID = clientUtteranceID
        self.source = source
        self.speaker = speaker
        self.sequence = sequence
        self.startedAtMs = startedAtMs
    }

    enum CodingKeys: String, CodingKey {
        case clientUtteranceID = "client_utterance_id"
        case source
        case speaker
        case sequence
        case startedAtMs = "started_at_ms"
    }
}

public struct UtteranceCommitMessage: Codable, Equatable, Sendable {
    public let clientUtteranceID: String
    public let sequence: Int
    public let endedAtMs: Int

    public init(clientUtteranceID: String, sequence: Int, endedAtMs: Int) {
        self.clientUtteranceID = clientUtteranceID
        self.sequence = sequence
        self.endedAtMs = endedAtMs
    }

    enum CodingKeys: String, CodingKey {
        case clientUtteranceID = "client_utterance_id"
        case sequence
        case endedAtMs = "ended_at_ms"
    }
}

public enum UtteranceCancelReason: String, Codable, Equatable, Sendable {
    case minimumSpeechDurationNotMet = "minimum_speech_duration_not_met"
    case audioPipelineOverflow = "audio_pipeline_overflow"
    case captureInterrupted = "capture_interrupted"
    case userInterrupted = "user_interrupted"
    case applicationShutdown = "application_shutdown"
}

public struct UtteranceCancelMessage: Codable, Equatable, Sendable {
    public let clientUtteranceID: String
    public let sequence: Int
    public let reason: UtteranceCancelReason

    public init(clientUtteranceID: String, sequence: Int, reason: UtteranceCancelReason) {
        self.clientUtteranceID = clientUtteranceID
        self.sequence = sequence
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case clientUtteranceID = "client_utterance_id"
        case sequence
        case reason
    }
}

public struct StopStreamMessage: Codable, Equatable, Sendable {
    public let source: AudioSource

    public init(source: AudioSource) {
        self.source = source
    }
}

public enum ClientControlMessage: Codable, Equatable, Sendable {
    case hello(HelloMessage)
    case startStream(StartStreamMessage)
    case utteranceStart(UtteranceStartMessage)
    case utteranceCommit(UtteranceCommitMessage)
    case utteranceCancel(UtteranceCancelMessage)
    case stopStream(StopStreamMessage)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum MessageType: String, Codable {
        case hello
        case startStream = "start_stream"
        case utteranceStart = "utterance_start"
        case utteranceCommit = "utterance_commit"
        case utteranceCancel = "utterance_cancel"
        case stopStream = "stop_stream"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MessageType.self, forKey: .type) {
        case .hello:
            self = .hello(try HelloMessage(from: decoder))
        case .startStream:
            self = .startStream(try StartStreamMessage(from: decoder))
        case .utteranceStart:
            self = .utteranceStart(try UtteranceStartMessage(from: decoder))
        case .utteranceCommit:
            self = .utteranceCommit(try UtteranceCommitMessage(from: decoder))
        case .utteranceCancel:
            self = .utteranceCancel(try UtteranceCancelMessage(from: decoder))
        case .stopStream:
            self = .stopStream(try StopStreamMessage(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(message):
            try container.encode(MessageType.hello, forKey: .type)
            try message.encode(to: encoder)
        case let .startStream(message):
            try container.encode(MessageType.startStream, forKey: .type)
            try message.encode(to: encoder)
        case let .utteranceStart(message):
            try container.encode(MessageType.utteranceStart, forKey: .type)
            try message.encode(to: encoder)
        case let .utteranceCommit(message):
            try container.encode(MessageType.utteranceCommit, forKey: .type)
            try message.encode(to: encoder)
        case let .utteranceCancel(message):
            try container.encode(MessageType.utteranceCancel, forKey: .type)
            try message.encode(to: encoder)
        case let .stopStream(message):
            try container.encode(MessageType.stopStream, forKey: .type)
            try message.encode(to: encoder)
        }
    }
}

public struct TranscriptDelta: Codable, Equatable, Sendable {
    public let clientUtteranceID: String
    public let openAIItemID: String
    public let sequence: Int
    public let source: AudioSource
    public let speaker: Speaker
    public let delta: String

    public init(
        clientUtteranceID: String,
        openAIItemID: String,
        sequence: Int,
        source: AudioSource,
        speaker: Speaker,
        delta: String
    ) {
        self.clientUtteranceID = clientUtteranceID
        self.openAIItemID = openAIItemID
        self.sequence = sequence
        self.source = source
        self.speaker = speaker
        self.delta = delta
    }

    enum CodingKeys: String, CodingKey {
        case clientUtteranceID = "client_utterance_id"
        case openAIItemID = "openai_item_id"
        case sequence
        case source
        case speaker
        case delta
    }
}

public struct TranscriptCompleted: Codable, Equatable, Sendable {
    public let clientUtteranceID: String
    public let openAIItemID: String
    public let sequence: Int
    public let source: AudioSource
    public let speaker: Speaker
    public let transcript: String

    public init(
        clientUtteranceID: String,
        openAIItemID: String,
        sequence: Int,
        source: AudioSource,
        speaker: Speaker,
        transcript: String
    ) {
        self.clientUtteranceID = clientUtteranceID
        self.openAIItemID = openAIItemID
        self.sequence = sequence
        self.source = source
        self.speaker = speaker
        self.transcript = transcript
    }

    enum CodingKeys: String, CodingKey {
        case clientUtteranceID = "client_utterance_id"
        case openAIItemID = "openai_item_id"
        case sequence
        case source
        case speaker
        case transcript
    }
}

public struct OverlayResult: Codable, Equatable, Sendable {
    public let utteranceID: String
    public let detectedLanguage: String
    public let originalText: String
    public let translationRU: String
    public let translationEN: String
    public let replyNeeded: Bool
    public let suggestedReplyRU: String
    public let suggestedReplyEN: String

    public init(
        utteranceID: String,
        detectedLanguage: String,
        originalText: String,
        translationRU: String,
        translationEN: String,
        replyNeeded: Bool,
        suggestedReplyRU: String,
        suggestedReplyEN: String
    ) {
        self.utteranceID = utteranceID
        self.detectedLanguage = detectedLanguage
        self.originalText = originalText
        self.translationRU = translationRU
        self.translationEN = translationEN
        self.replyNeeded = replyNeeded
        self.suggestedReplyRU = suggestedReplyRU
        self.suggestedReplyEN = suggestedReplyEN
    }

    enum CodingKeys: String, CodingKey {
        case utteranceID = "utterance_id"
        case detectedLanguage = "detected_language"
        case originalText = "original_text"
        case translationRU = "translation_ru"
        case translationEN = "translation_en"
        case replyNeeded = "reply_needed"
        case suggestedReplyRU = "suggested_reply_ru"
        case suggestedReplyEN = "suggested_reply_en"
    }
}

public struct OverlayResultMessage: Codable, Equatable, Sendable {
    public let clientUtteranceID: String
    public let sequence: Int
    public let result: OverlayResult

    public init(clientUtteranceID: String, sequence: Int, result: OverlayResult) {
        self.clientUtteranceID = clientUtteranceID
        self.sequence = sequence
        self.result = result
    }

    enum CodingKeys: String, CodingKey {
        case clientUtteranceID = "client_utterance_id"
        case sequence
        case result
    }
}

public struct RecoverableErrorMessage: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let clientUtteranceID: String?

    public init(code: String, message: String, clientUtteranceID: String? = nil) {
        self.code = code
        self.message = message
        self.clientUtteranceID = clientUtteranceID
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case clientUtteranceID = "client_utterance_id"
    }
}

public enum SessionStatus: String, Codable, Equatable, Sendable {
    case connected
    case ready
    case degraded
    case closed
}

public struct SessionStateMessage: Codable, Equatable, Sendable {
    public let status: SessionStatus
    public let sessionID: UUID

    public init(status: SessionStatus, sessionID: UUID) {
        self.status = status
        self.sessionID = sessionID
    }

    enum CodingKeys: String, CodingKey {
        case status
        case sessionID = "session_id"
    }
}

public struct FatalErrorMessage: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ServerMessage: Codable, Equatable, Sendable {
    case sessionState(SessionStateMessage)
    case transcriptDelta(TranscriptDelta)
    case transcriptCompleted(TranscriptCompleted)
    case overlayResult(OverlayResultMessage)
    case recoverableError(RecoverableErrorMessage)
    case fatalError(FatalErrorMessage)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum MessageType: String, Codable {
        case sessionState = "session_state"
        case transcriptDelta = "transcript_delta"
        case transcriptCompleted = "transcript_completed"
        case overlayResult = "overlay_result"
        case recoverableError = "recoverable_error"
        case fatalError = "fatal_error"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MessageType.self, forKey: .type) {
        case .sessionState:
            self = .sessionState(try SessionStateMessage(from: decoder))
        case .transcriptDelta:
            self = .transcriptDelta(try TranscriptDelta(from: decoder))
        case .transcriptCompleted:
            self = .transcriptCompleted(try TranscriptCompleted(from: decoder))
        case .overlayResult:
            self = .overlayResult(try OverlayResultMessage(from: decoder))
        case .recoverableError:
            self = .recoverableError(try RecoverableErrorMessage(from: decoder))
        case .fatalError:
            self = .fatalError(try FatalErrorMessage(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sessionState(message):
            try container.encode(MessageType.sessionState, forKey: .type)
            try message.encode(to: encoder)
        case let .transcriptDelta(message):
            try container.encode(MessageType.transcriptDelta, forKey: .type)
            try message.encode(to: encoder)
        case let .transcriptCompleted(message):
            try container.encode(MessageType.transcriptCompleted, forKey: .type)
            try message.encode(to: encoder)
        case let .overlayResult(message):
            try container.encode(MessageType.overlayResult, forKey: .type)
            try message.encode(to: encoder)
        case let .recoverableError(message):
            try container.encode(MessageType.recoverableError, forKey: .type)
            try message.encode(to: encoder)
        case let .fatalError(message):
            try container.encode(MessageType.fatalError, forKey: .type)
            try message.encode(to: encoder)
        }
    }
}

public extension JSONEncoder {
    static var protocolEncoder: JSONEncoder {
        JSONEncoder()
    }
}

public extension JSONDecoder {
    static var protocolDecoder: JSONDecoder {
        JSONDecoder()
    }
}
