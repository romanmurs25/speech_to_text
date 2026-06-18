# Concise Implementation Plan

## Goal

Build a working vertical slice of LiveOverlayTranslator that runs without an API key in mock mode, validates and tests the backend protocol and response pipeline, provides a native macOS overlay shell with mock events, and establishes real microphone, Realtime, Responses, and Clean Share boundaries for production completion.

## Phases

1. Documentation and contracts
   - Create architecture, protocol, privacy, README, `.env.example`, and `.gitignore`.
   - Define shared client/server WebSocket message contracts.

2. Backend vertical slice
   - Scaffold Node.js 22, TypeScript strict mode, Fastify, `ws`, OpenAI SDK, Zod, pino, and Vitest.
   - Add Zod validation for all control messages and server messages.
   - Add session, correlation, dialogue context, deduplication, redaction, mock Realtime, mock Responses, and WebSocket handling.
   - Add tests for malformed control messages, item correlation, out-of-order completions, duplicates, dialogue context, structured output parsing, mock OpenAI events, Responses error paths, and redaction.

3. macOS vertical slice
   - Scaffold Swift 6 package and Xcode project files under `macos`.
   - Add SwiftUI app shell hosted by an AppKit `NSPanel`.
   - Add Codable protocol messages, overlay state, transcript assembler, dialogue store, endpoint detector, PCM helpers, backend WebSocket shell, mock event source, and Clean Share coordinator shell.
   - Add unit tests for Codable round trips, endpointing, pre-roll, transcript assembly, sequence ordering, stale-result protection, dialogue context rules, and mock end-to-end overlay updates.

4. Real integrations
   - Backend Realtime client connects to the GA Realtime WebSocket endpoint using `gpt-realtime-whisper`.
   - Backend Responses client calls the official SDK with Structured Outputs, `store: false`, and `OPENAI_TEXT_MODEL || "gpt-5.4-mini"`.
   - macOS microphone capture streams PCM through the endpoint detector to the backend.
   - Clean Share coordinator uses ScreenCaptureKit to create a self-excluding clean feed window.

5. Verification and limitations
   - Run available server install, type check, tests, and build.
   - Run available Swift tests/builds when Xcode/Swift tooling is present.
   - Document any macOS runtime behavior that cannot be verified without granting permissions or running the GUI locally.

## Current Slice Acceptance

- Mock backend runs without `OPENAI_API_KEY`.
- A mock final transcript produces a translated overlay result.
- Only completed transcripts call the overlay response service.
- Duplicate and out-of-order events are reconciled.
- API key references are backend-only.
- Overlay is implemented as a translucent always-on-top `NSPanel`.
- Clean Share code creates a separate clean feed coordinator and excludes app windows where ScreenCaptureKit is available.
- Tests cover protocol, ordering, deduplication, privacy redaction, Swift state, and endpoint behavior.
