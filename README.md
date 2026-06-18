# LiveOverlayTranslator

LiveOverlayTranslator is a native macOS microphone-to-overlay prototype with a Node.js backend. The current P0 build focuses on one reliable path:

```text
microphone -> local endpoint detection -> small PCM WebSocket frames -> backend -> OpenAI Realtime transcription -> completed transcript -> OpenAI Responses translation -> translucent macOS overlay
```

System audio and Clean Share are not implemented in this P0 build. The app must not be used as a production meeting privacy tool yet.

## Repository Layout

```text
/macos   Swift 6 macOS app, SwiftUI/AppKit overlay, microphone capture
/server  Node.js 22 TypeScript backend, Fastify, ws, OpenAI SDK, Zod
/docs    Architecture, protocol, privacy, and validation notes
```

## Backend Setup

```bash
cd server
npm ci
cp ../.env.example .env
npm run dev
```

Mock mode works without an API key when `MOCK_OPENAI=true`.

For real OpenAI API calls, set these only in your local backend environment:

```bash
MOCK_OPENAI=false
OPENAI_API_KEY=
OPENAI_REALTIME_MODEL=gpt-realtime-whisper
OPENAI_TEXT_MODEL=gpt-5.4-mini
OPENAI_REALTIME_DELAY=low
```

Never put an OpenAI key in Swift source, Info.plist, entitlements, Xcode settings, UserDefaults, committed docs, or test fixtures.

## Verified Backend Commands

```bash
cd server
npm run typecheck
npm test
npm run build
```

Verified in this workspace on 2026-06-19:

- `npm run typecheck` passed for source and test TypeScript.
- `npm test` passed: 11 files, 51 tests.
- `npm run build` passed.

## macOS Setup

The Swift package lives at `macos/LiveOverlayTranslator`.

```bash
cd macos/LiveOverlayTranslator
swift build
swift test
```

Open `macos/LiveOverlayTranslator/LiveOverlayTranslator.xcodeproj` in full Xcode for the native app target. Minimum macOS version is 14.

In this workspace on 2026-06-19, `swift build` passed with SwiftPM module caches redirected to `/private/tmp`. `swift test` is blocked because the active Command Line Tools toolchain does not provide the Swift `Testing` module, and `xcodebuild` is blocked because the active developer directory is `/Library/Developer/CommandLineTools` rather than full Xcode.

## Flow A: Local Mock

1. Launch the macOS app.
2. Open the control window.
3. Select `Local Mock`.
4. Click `Start Listening`.
5. Verify the overlay visibly shows provisional text, finalized transcript, pending translation, Russian/English translations, and empty suggested replies for the microphone/local mock.

Local Mock does not connect to the backend, does not request microphone permission, and does not require an API key.

## Flow B: Backend Mock

Backend:

```bash
cd server
cp ../.env.example .env
# in .env:
# MOCK_OPENAI=true
# OPENAI_API_KEY=
npm run dev
```

macOS app:

1. Select `Backend`.
2. Set Backend WebSocket URL to `ws://127.0.0.1:8787/ws`.
3. Click `Start Listening`.
4. Grant microphone permission if prompted.
5. Speak one phrase.
6. Verify microphone PCM is streamed as multiple bounded frames and exactly one commit is sent after local endpoint detection.
7. Verify the backend mock completion reaches the overlay.

## Flow C: Real OpenAI Microphone

Backend `.env`:

```bash
MOCK_OPENAI=false
OPENAI_API_KEY=
OPENAI_REALTIME_MODEL=gpt-realtime-whisper
OPENAI_TEXT_MODEL=gpt-5.4-mini
OPENAI_REALTIME_DELAY=low
```

Then:

1. Start the backend with `npm run dev`.
2. Launch the macOS app.
3. Select `Backend`.
4. Set Backend WebSocket URL to `ws://127.0.0.1:8787/ws`.
5. Click `Start Listening`.
6. Grant microphone permission.
7. Speak one English phrase.
8. Confirm a real final transcript appears.
9. Confirm Russian and English rendering appears after the completed transcript.
10. Confirm suggested reply behavior.
11. Click `Stop Listening`.
12. Verify normal stop does not show a false disconnect warning.

For production deployment, use WSS for the backend WebSocket. Plain `ws://127.0.0.1:8787/ws` is for local development only.

## Current P0 Capabilities

- Explicit Local Mock mode with delayed visual states.
- Backend mode using `BackendWebSocketClient`.
- Microphone capture through AVFoundation only after Start Listening.
- Local endpoint detection with pre-roll, phrase-ending silence, minimum duration, and maximum utterance duration.
- Incremental PCM S16LE mono 24 kHz frames, default 100 ms per frame.
- Swift protocol support for `session_state`, transcript messages, overlay result, `recoverable_error`, and `fatal_error`.
- Generation-bound macOS Backend microphone session ownership with one resource set per active session.
- Stop during startup or microphone permission invalidates the session before capture can start.
- Backend Realtime readiness queue for append/commit before `session.updated`.
- Backend `utterance_cancel` support, OpenAI input-buffer clear, and fail-closed handling for ambiguous overlapping utterances.
- Backend Realtime readiness queue byte/event overflow as a terminal Realtime-session failure.
- Backend terminal Realtime failure closes the client WebSocket; the user must explicitly start a new session.
- Translation failure preserves completed speech in future dialogue context.

## Not Ready

- System audio capture is unavailable.
- Clean Share is unavailable; sharing Entire Screen can expose the overlay.
- Simultaneous microphone/system-audio multiplexing is unsupported.
- Production use, notarization, and distribution are out of scope for this P0 build.

## Privacy Defaults

- `OPENAI_API_KEY` exists only on the backend.
- Raw audio is not logged.
- Transcript text is redacted in production logs by default.
- Responses API requests set `store: false`.
- Suggested replies are not treated as real dialogue unless marked used or later confirmed by microphone transcription.

See `docs/privacy.md` and `docs/p0-microphone-report.md` for details.
