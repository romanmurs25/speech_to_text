# LiveOverlayTranslator Architecture

## Purpose

LiveOverlayTranslator is a native macOS application with a local overlay and a backend API bridge. The app captures speech, detects completed utterances locally, streams PCM audio to the backend, receives transcription updates, asks the backend for bilingual translation and reply suggestions only after final transcripts, and displays the result in a translucent always-on-top overlay.

The backend is the only component that owns `OPENAI_API_KEY`. The macOS app talks only to the backend over WebSocket and never bundles a standard OpenAI API key.

## Data Flow

1. The macOS app starts a client session and sends a `hello` control message to the backend WebSocket.
2. `ApplicationController` creates one generation-bound `BackendMicrophoneSessionContext` that owns exactly one backend session UUID, WebSocket client, audio coordinator, microphone service, bounded pipe, receive task, processing task, cleanup task, and invalidation token.
3. The selected P0 audio source starts:
   - `microphone` uses `MicrophoneAudioCaptureService` and labels speech as `local`.
   - `systemAudio` is unavailable in the current app UI and fails safely if called internally.
4. Microphone permission is requested before an AVAudioEngine input tap is installed. After every async startup step, the app checks that the same session context is still current.
5. Captured audio is converted to PCM S16LE, mono, 24 kHz by `PCMResampler`.
6. `SpeechEndpointDetector` maintains an adaptive noise floor, pre-roll, start confirmation, phrase-ending silence, maximum duration, and minimum non-silent duration.
7. `AudioStreamCoordinator` sends:
   - `start_stream`
   - `utterance_start`
   - binary PCM audio frames
   - `utterance_commit`
   - `utterance_cancel` for discarded or interrupted uncommitted utterances
   It uses `SessionCommitArbiter` to atomically decide whether overflow/invalidation or commit admission wins. Once commit admission wins, later overflow can terminate the session but must not claim that the utterance was cancelled.
8. The backend validates JSON control messages with Zod in `ClientProtocolValidator`.
9. `ClientSessionManager` owns one active microphone Realtime transcription client for the P0 stream.
10. The backend forwards PCM chunks to OpenAI Realtime using `input_audio_buffer.append`, clears discarded audio using `input_audio_buffer.clear`, then commits local endpointed phrases using `input_audio_buffer.commit`.
11. `UtteranceCorrelationStore` tracks each utterance through `active`, `commitRequested`, `correlated`, `completed`, `cancelled`, or `abandoned` states and maps committed client utterance IDs to OpenAI item IDs when OpenAI acknowledges committed audio.
12. `RealtimeEventRouter` emits provisional `transcript_delta` messages as subdued overlay text.
13. Only `conversation.item.input_audio_transcription.completed` creates a final utterance envelope.
14. `DialogueContextService` selects the latest 8 to 12 verified real speech turns. AI suggested replies are excluded unless the user marks them used or later local microphone transcription confirms the user spoke them.
15. `OverlayResponseService` deduplicates by `session_id` plus `utterance_id`, calls `OpenAIResponsesClient` with the client-session abort signal, and emits an `overlay_result` only while the session is still alive.
16. `OverlayState` applies deltas, completions, and overlay results using utterance IDs and sequence numbers so stale results cannot overwrite newer cards.
17. `OverlayWindowController` displays the SwiftUI overlay in an `NSPanel`.
18. `CleanShareCoordinator` is unavailable in P0 and must not claim screen-share safety until a real `SCContentFilter`, `SCStream`, output handler, renderer, and started capture exist.

## macOS Component Boundaries

- `AudioCaptureService`: common protocol for source-specific audio capture.
- `MicrophoneAudioCaptureService`: AVFoundation microphone permission checks and capture startup. Permission request and input-tap installation are separate so Stop can invalidate startup while the macOS prompt is open.
- `SystemAudioCaptureService`: unavailable P0 stub; future system-audio expansion can be added behind `AudioCaptureService`.
- `PCMResampler`: converts samples to mono 24 kHz PCM S16LE.
- `SpeechEndpointDetector`: replaceable local speech boundary detector.
- `EnergySpeechEndpointDetector`: initial detector with settings-driven thresholds and pre-roll.
- `SessionInvalidationToken`: thread-safe first-writer-wins session invalidation reason shared by capture callbacks, processing tasks, and cleanup.
- `BackendMicrophoneSessionContext`: generation-bound owner for one backend microphone session resource set.
- `AudioStreamCoordinator`: bridges capture, endpoint detection, protocol messages, commit admission, and invalidation-aware cancellation.
- `SessionCommitArbiter`: first-writer-wins primitive for overflow versus commit admission. It records whether a commit was admitted, sent, completed, invalidated before admission, or invalidated after admission.
- `BoundedAudioChunkPipe`: bounded capture-to-processing pipe; overflow synchronously invalidates the session, finishes the stream, rejects later chunks, and does not call `AsyncStream` continuation methods or callbacks while holding its internal lock.
- `BackendWebSocketClient`: Codable WebSocket client for JSON control messages and binary frames.
- `TranscriptAssembler`: merges streaming deltas and final replacements per utterance.
- `DialogueStore`: stores only verified finalized real speech turns.
- `OverlayState`: main-thread app state, stale-result protection, mock mode.
- `OverlayWindowController`: non-activating translucent `NSPanel`.
- `CleanShareCoordinator`: unavailable P0 stub; future Clean Share must implement ScreenCaptureKit filtering, stream output, rendering, diagnostics, and lifecycle cleanup before exposing a start control.
- `GlobalShortcutController`: global hide/show and emergency-hide hotkeys.
- `TerminationReplyGate`: reply-once primitive used by the AppKit termination path so cleanup completion and timeout cannot both reply to macOS.

## Server Component Boundaries

- `ClientSessionManager`: owns session lifecycle, source stream state, message limits, fail-closed interruption behavior, and terminalization of client close/error/send-failure paths.
- `ClientProtocolValidator`: Zod validation for all JSON client messages.
- `OpenAIRealtimeTranscriptionClient`: interface for OpenAI Realtime WebSocket sessions, including bounded readiness queues, `clear`, and terminal failure callbacks.
- `RealtimeEventRouter`: converts OpenAI Realtime events into application protocol events.
- `UtteranceCorrelationStore`: correlates client utterance IDs, sequence numbers, and OpenAI item IDs without relying on event order.
- `DialogueContextService`: creates verified dialogue context windows.
- `OverlayResponseService`: deduplicates final utterances, calls the Responses client with session cancellation, normalizes refusal, abort, and parse failures.
- `OpenAIResponsesClient`: interface over the official OpenAI JavaScript SDK Responses API and Structured Outputs.
- `RequestDeduplicator`: per-session idempotency guard for final utterances.
- `SafeClientWebSocketSession`: wraps accepted client sockets with safe send, safe close, error handling, and exactly-once manager closure.

## WebSocket Protocol

JSON control messages and binary PCM audio frames share one connection. Production deployments must use WSS behind TLS. Server-side limits enforce maximum frame size, per-session rate limiting, bounded audio buffers, and bounded dialogue context. The full message contract is documented in `docs/protocol.md`.

## OpenAI Integration Decisions

- Realtime transcription uses the GA Realtime WebSocket API with a transcription session and `gpt-realtime-whisper`.
- The app performs local endpoint detection, so server-side Realtime turn detection is omitted or explicitly set to null.
- The P0 app exposes one microphone Realtime transcription session. Simultaneous microphone/system-audio multiplexing needs a future protocol change because binary audio frames currently have no stream identifier.
- Audio chunks are appended as base64 PCM16. Local utterance boundaries trigger `input_audio_buffer.commit`.
- Discarded or interrupted active utterances trigger `input_audio_buffer.clear`, not a commit.
- Overflow before commit admission sends no `utterance_commit`, cancels the active utterance, and ends the session.
- Overflow after commit admission may find a commit already in flight or already across the local protocol boundary. The app ends the session and treats unfinished output as abandoned/uncertain instead of claiming successful cancellation. Audio is never replayed automatically.
- Completion reconciliation uses OpenAI `item_id`, not arrival order.
- Translation and reply generation use the Responses API with Structured Outputs, `store: false`, `reasoning.effort: none`, and an overrideable text model defaulting to `gpt-5.4-mini`.

## Privacy Decisions

- Standard OpenAI API keys stay on the backend.
- The macOS app sends audio only to the configured backend.
- The backend sends audio to OpenAI Realtime only while a stream is active.
- The backend sends finalized transcript text and verified recent context to the Responses API.
- Raw audio is never logged.
- Transcript text and API credentials are redacted by default.
- Responses requests set `store: false`.
- Responses requests are aborted when the client WebSocket closes, a fatal session termination occurs, ambiguous routing is detected, or Realtime terminal failure ends the session. Aborted work is not cached by the deduplicator and does not show a late translation error after the session has ended.
- In-memory audio buffers are cleared after commit, interruption, or failure.
- Clean Share is not implemented. Sharing the physical Entire Screen source can expose the overlay.

## Error Handling

The app and backend model these cases explicitly:

- microphone permission denied;
- screen-recording permission denied;
- audio device changes;
- WebSocket disconnect or backend restart;
- OpenAI disconnect;
- Realtime readiness queue overflow;
- Realtime socket send failure;
- client WebSocket send failure or error event;
- ambiguous audio routing;
- active utterance cancellation;
- abandoned post-commit utterances;
- malformed client or OpenAI events;
- rate limits;
- empty transcripts;
- duplicate completion events;
- out-of-order completion events;
- Responses API timeout, refusal, or invalid structured output;
- application sleep and wake.

Automatic reconnect is not implemented in P0. A terminal backend, Realtime, client WebSocket, or remote `session_state.closed` failure ends the current session, stops microphone capture, closes the client WebSocket when applicable, and requires the user to explicitly press Start Listening again. The app does not replay committed or uncertain audio because replay can create duplicate transcriptions. Active uncommitted utterances are cancelled; post-commit unfinished utterances are abandoned.

## Implementation Phases

1. Backend protocol, mock mode, response schema, redaction, and tests.
2. macOS shell, overlay NSPanel, mock event flow, status/settings, and unit tests.
3. Microphone capture, PCM conversion, endpoint detection, backend streaming, Realtime integration.
4. System audio capture, independent local and remote streams, timestamp ordering.
5. Clean Share capture, self-window exclusion, emergency hide shortcut, diagnostics, and permission UX.

This repository implements a P0 microphone vertical slice across phases 1, 2, and selected phase 3: backend mock mode and protocol tests, real Responses client boundary, Swift overlay state and NSPanel shell, endpoint detector tests, microphone capture, bounded PCM streaming, Realtime client readiness handling, generation-bound macOS session ownership, remote-close cleanup, cancellation/clear semantics for interrupted utterances, atomic overflow/commit arbitration, abandoned post-commit semantics, bounded app termination reply, and explicit unavailable states for system audio and Clean Share.
