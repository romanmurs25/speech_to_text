# LiveOverlayTranslator Architecture

## Purpose

LiveOverlayTranslator is a native macOS application with a local overlay and a backend API bridge. The app captures speech, detects completed utterances locally, streams PCM audio to the backend, receives transcription updates, asks the backend for bilingual translation and reply suggestions only after final transcripts, and displays the result in a translucent always-on-top overlay.

The backend is the only component that owns `OPENAI_API_KEY`. The macOS app talks only to the backend over WebSocket and never bundles a standard OpenAI API key.

## Data Flow

1. The macOS app starts a client session and sends a `hello` control message to the backend WebSocket.
2. The selected audio source starts:
   - `microphone` uses `MicrophoneAudioCaptureService` and labels speech as `local`.
   - `systemAudio` uses `SystemAudioCaptureService` and labels speech as `remote`.
   - `both` runs one independent stream per source so overlapping speakers are not mixed.
3. Captured audio is converted to PCM S16LE, mono, 24 kHz by `PCMResampler`.
4. `SpeechEndpointDetector` maintains an adaptive noise floor, pre-roll, start confirmation, phrase-ending silence, maximum duration, and minimum non-silent duration.
5. `AudioStreamCoordinator` sends:
   - `start_stream`
   - `utterance_start`
   - binary PCM audio frames
   - `utterance_commit`
6. The backend validates JSON control messages with Zod in `ClientProtocolValidator`.
7. `ClientSessionManager` owns one `OpenAIRealtimeTranscriptionClient` per logical source.
8. The backend forwards PCM chunks to OpenAI Realtime using `input_audio_buffer.append`, then commits local endpointed phrases using `input_audio_buffer.commit`.
9. `UtteranceCorrelationStore` maps pending client utterance IDs to OpenAI item IDs when OpenAI acknowledges committed audio.
10. `RealtimeEventRouter` emits provisional `transcript_delta` messages as subdued overlay text.
11. Only `conversation.item.input_audio_transcription.completed` creates a final utterance envelope.
12. `DialogueContextService` selects the latest 8 to 12 verified real speech turns. AI suggested replies are excluded unless the user marks them used or later local microphone transcription confirms the user spoke them.
13. `OverlayResponseService` deduplicates by `session_id` plus `utterance_id`, calls `OpenAIResponsesClient`, and emits an `overlay_result`.
14. `OverlayState` applies deltas, completions, and overlay results using utterance IDs and sequence numbers so stale results cannot overwrite newer cards.
15. `OverlayWindowController` displays the SwiftUI overlay in an `NSPanel`.
16. `CleanShareCoordinator` can create a ScreenCaptureKit clean feed window that excludes all windows owned by LiveOverlayTranslator. The app never claims that it can hide overlays from unrelated third-party full-screen capture.

## macOS Component Boundaries

- `AudioCaptureService`: common protocol for source-specific audio capture.
- `MicrophoneAudioCaptureService`: AVFoundation microphone capture, permission checks, and device-change handling.
- `SystemAudioCaptureService`: ScreenCaptureKit system audio/display capture boundary. The first vertical slice ships the abstraction and permission surface; production system-audio expansion can be added behind this protocol.
- `PCMResampler`: converts samples to mono 24 kHz PCM S16LE.
- `SpeechEndpointDetector`: replaceable local speech boundary detector.
- `EnergySpeechEndpointDetector`: initial detector with settings-driven thresholds and pre-roll.
- `AudioStreamCoordinator`: bridges capture, endpoint detection, protocol messages, and retry state.
- `BackendWebSocketClient`: Codable WebSocket client for JSON control messages and binary frames.
- `TranscriptAssembler`: merges streaming deltas and final replacements per utterance.
- `DialogueStore`: stores only verified finalized real speech turns.
- `OverlayState`: main-thread app state, stale-result protection, mock mode.
- `OverlayWindowController`: non-activating translucent `NSPanel`.
- `CleanShareCoordinator`: ScreenCaptureKit display capture, self-window exclusion, clean feed state, diagnostics.
- `GlobalShortcutController`: global hide/show and emergency-hide hotkeys.

## Server Component Boundaries

- `ClientSessionManager`: owns session lifecycle, source stream state, message limits, and reconnect-safe interruption behavior.
- `ClientProtocolValidator`: Zod validation for all JSON client messages.
- `OpenAIRealtimeTranscriptionClient`: interface for OpenAI Realtime WebSocket sessions.
- `RealtimeEventRouter`: converts OpenAI Realtime events into application protocol events.
- `UtteranceCorrelationStore`: correlates client utterance IDs, sequence numbers, and OpenAI item IDs without relying on event order.
- `DialogueContextService`: creates verified dialogue context windows.
- `OverlayResponseService`: deduplicates final utterances, calls the Responses client, normalizes refusal and parse failures.
- `OpenAIResponsesClient`: interface over the official OpenAI JavaScript SDK Responses API and Structured Outputs.
- `RequestDeduplicator`: per-session idempotency guard for final utterances.

## WebSocket Protocol

JSON control messages and binary PCM audio frames share one connection. Production deployments must use WSS behind TLS. Server-side limits enforce maximum frame size, per-session rate limiting, bounded audio buffers, and bounded dialogue context. The full message contract is documented in `docs/protocol.md`.

## OpenAI Integration Decisions

- Realtime transcription uses the GA Realtime WebSocket API with a transcription session and `gpt-realtime-whisper`.
- The app performs local endpoint detection, so server-side Realtime turn detection is omitted or explicitly set to null.
- Every source gets an independent Realtime transcription session.
- Audio chunks are appended as base64 PCM16. Local utterance boundaries trigger `input_audio_buffer.commit`.
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
- In-memory audio buffers are cleared after commit, interruption, or failure.
- The Clean Feed only protects the share flow where the user shares the generated Clean Feed window. It does not control a conference app that captures the physical display directly.

## Error Handling

The app and backend model these cases explicitly:

- microphone permission denied;
- screen-recording permission denied;
- audio device changes;
- WebSocket disconnect or backend restart;
- OpenAI disconnect;
- malformed client or OpenAI events;
- rate limits;
- empty transcripts;
- duplicate completion events;
- out-of-order completion events;
- Responses API timeout, refusal, or invalid structured output;
- application sleep and wake.

Reconnect uses bounded backoff with jitter. The app does not automatically replay committed audio after uncertain disconnects because replay can create duplicate transcriptions. The affected utterance is marked interrupted and can expose a safe retry path for text-only work.

## Implementation Phases

1. Backend protocol, mock mode, response schema, redaction, and tests.
2. macOS shell, overlay NSPanel, mock event flow, status/settings, and unit tests.
3. Microphone capture, PCM conversion, endpoint detection, backend streaming, Realtime integration.
4. System audio capture, independent local and remote streams, timestamp ordering.
5. Clean Share capture, self-window exclusion, emergency hide shortcut, diagnostics, and permission UX.

This repository implements a working vertical slice across phases 1, 2, and selected phase 3 and phase 5 boundaries: backend mock mode and protocol tests, real Responses client boundary, Swift overlay state and NSPanel shell, endpoint detector tests, microphone-capture scaffolding, Realtime client boundary, and Clean Share ScreenCaptureKit coordinator shell.
