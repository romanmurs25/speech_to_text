# P0 Microphone Vertical Slice Report

Report date: 2026-06-18

## Initial Repository State

- Branch: `main`, tracking `origin/main`.
- Latest commits at start:
  - `8782133 Audit and stabilize LiveOverlayTranslator`
  - `1cedd54 Initial LiveOverlayTranslator vertical slice`
- Working tree at start: clean.
- Existing audit docs were preserved.

## Baseline Findings

- The app launched `MockOverlayEventSource` automatically from `AppDelegate` and did not compose the backend WebSocket, microphone capture, audio coordinator, or receive loop.
- Swift `ServerMessage` supported only transcript delta/completed, overlay result, and recoverable error; it could not decode the backend's first `session_state` message or `fatal_error`.
- App Sandbox was enabled but `com.apple.security.network.client` was missing.
- `AudioStreamCoordinator` sent a full detected utterance as one binary frame after endpointing instead of streaming bounded PCM frames during speech.
- `EnergySpeechEndpointDetector` checked maximum utterance duration only in the silence branch.
- `OpenAIRealtimeTranscriptionClient` silently dropped append/commit events before the Realtime WebSocket was open.
- Backend completed speech was added to dialogue context only after translation succeeded.
- `CleanShareCoordinator` exposed a misleading share-safety label even though no `SCStream` was created or started.
- `SystemAudioCaptureService` only probed `SCShareableContent` and did not capture audio.

## Initial Commands

| Command | Exit | Evidence |
| --- | ---: | --- |
| `git status -sb` | 0 | `## main...origin/main` |
| `git log --oneline --decorate -10` | 0 | two commits listed. |
| `rg --files ...` | 0 | repository inventory collected. |
| `rg TODO/FIXME/...` | 0 | found hardcoded mock path, misleading Clean Share placeholder, OpenAI key docs references, and unsupported SystemAudio/CleanShare surfaces. |

## Work Performed

- Added Swift protocol parity for all current server messages: `session_state`, `transcript_delta`, `transcript_completed`, `overlay_result`, `recoverable_error`, and `fatal_error`.
- Added overlay state transitions for connected, degraded, closed, and fatal states.
- Added outbound sandbox network entitlement and local-network ATS exception for development WebSocket use.
- Replaced automatic launch-time mock playback with an `ApplicationController` and explicit control UI.
- Added selectable `Local Mock` and `Backend` modes, persisted mode/backend URL, visible source/status/error fields, and Start/Stop controls.
- Wired backend mode through `BackendWebSocketClient`, `AudioStreamCoordinator`, and `MicrophoneAudioCaptureService`.
- Added bounded `AsyncStream` handoff from AVAudioEngine callback to coordinator.
- Refactored `BackendWebSocketClient` to async connect, a testable transport protocol, URLSession WebSocket open observation, a single receive loop guard, and intentional disconnect handling.
- Redesigned endpoint detection events to stream initial pre-roll once, then incremental samples, then end/discard events.
- Added `PCMFrameChunker` with default 100 ms frames and little-endian Int16 serialization.
- Updated `AudioStreamCoordinator` to send bounded binary frames during speech and commit exactly once on endpoint end.
- Added backend Realtime readiness state, bounded append/commit queue, session acknowledgement flush, explicit OpenAI error handling, and intentional close handling.
- Added backend P0 safety: unsupported system audio start is rejected and overlapping active utterances do not overwrite active routing.
- Changed completed-transcript handling so verified speech is added to dialogue context before translation; translation failure no longer removes it from future context.
- Marked system audio and Clean Share unavailable instead of presenting placeholder success states.
- Updated README, privacy notes, architecture notes, protocol docs, manual checklist, and this report for P0 microphone-only behavior.

## Files Changed

- `README.md`
- `docs/architecture.md`
- `docs/protocol.md`
- `docs/privacy.md`
- `docs/manual-macos-test-checklist.md`
- `docs/acceptance-report.md`
- `docs/p0-microphone-report.md`
- `server/src/openai/OpenAIRealtimeTranscriptionClient.ts`
- `server/src/ws/ClientSessionManager.ts`
- `server/tests/clientSessionManager.test.ts`
- `server/tests/openAIRealtimeClient.test.ts`
- `macos/LiveOverlayTranslator/Info.plist`
- `macos/LiveOverlayTranslator/LiveOverlayTranslator.entitlements`
- `macos/LiveOverlayTranslator/LiveOverlayTranslator.xcodeproj/project.pbxproj`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/ApplicationController.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/LiveOverlayTranslatorApp.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/OverlayWindowController.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/MicrophoneAudioCaptureService.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/SystemAudioCaptureService.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/CleanShareCoordinator.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/AudioCaptureService.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/AudioStreamCoordinator.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/BackendWebSocketClient.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/MockOverlayEventSource.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/OverlayState.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/ProtocolModels.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/SpeechEndpointDetector.swift`
- `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/BackendWebSocketClientTests.swift`
- `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/MockEndToEndTests.swift`
- `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/OverlayStateTests.swift`
- `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/ProtocolModelsTests.swift`
- `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/SpeechEndpointDetectorTests.swift`

## Defects Fixed

1. App no longer launches canned mock automatically; mock is explicit Local Mock mode.
2. Backend mode now constructs real WebSocket, coordinator, microphone capture, receive loop, and shutdown path.
3. Swift decodes first backend `session_state` response and `fatal_error`.
4. Sandbox now includes outbound network client entitlement.
5. Audio is streamed in small PCM frames while speaking instead of one final utterance frame.
6. 100 ms frame chunking keeps frames far below the 256 KiB backend limit.
7. Endpoint maximum duration is checked during continuous speech.
8. Realtime append/commit events are queued until `session.updated` instead of silently dropped.
9. Intentional Realtime close no longer invokes unexpected disconnect handling.
10. Translation failure preserves the completed speech turn in future context.
11. P0 backend rejects unsupported system audio and overlapping active utterances.
12. Clean Share and system audio no longer present false ready/safe states.

## Intentionally Deferred

- Real system audio capture with ScreenCaptureKit audio output.
- True simultaneous local/remote multiplexing. The protocol needs stream/source tagging for binary frames before this is safe.
- Real Clean Share with `SCContentFilter`, `SCStream`, output handling, frame rendering, and manual privacy validation.
- Production WSS deployment, notarization, packaging, terminal-failure restart UX, sleep/wake hardening, and device-disconnect hardening.

## Final Validation

| Command | Exit | Result |
| --- | ---: | --- |
| `npm test` | 1 | Initial regression run failed before test/implementation corrections. |
| `npm test` | 0 | Backend tests passed. |
| `npm run typecheck` | 2 | Initial run caught a `Source` type mismatch after narrowing realtime client map keys. |
| `npm run typecheck` | 0 | TypeScript strict check passed. |
| `npm test` | 0 | Backend tests passed again: 9 files, 30 tests. |
| `npm run build` | 0 | Backend TypeScript build passed. |
| `swift build` | 1 | Sandboxed run failed before project compilation because SwiftPM/clang tried inaccessible user caches and the local CLT SDK/compiler were mismatched. |
| `env CLANG_MODULE_CACHE_PATH=/private/tmp/liveoverlay-clang-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/liveoverlay-swift-cache swift build` | 1 | Sandboxed run failed with `sandbox-exec: sandbox_apply: Operation not permitted`. |
| same `swift build` command outside sandbox | 1 | First real compile caught Swift 6 `NSLock` async-context and missing stream return issues. |
| same `swift build` command outside sandbox | 1 | Second real compile caught Swift 6 Sendable isolation for microphone capture. |
| same `swift build` command outside sandbox | 0 | Swift package and executable target built successfully. |
| same env with `swift test` outside sandbox | 1 | Test target failed before execution: installed Command Line Tools do not provide module `Testing`. |
| `xcode-select -p` | 0 | Active developer directory is `/Library/Developer/CommandLineTools`. |
| `swift --version` | 0 | Apple Swift 6.2 reported. |
| `xcodebuild -version` | 1 | Full Xcode is not selected/available. |
| `xcodebuild -list -project LiveOverlayTranslator.xcodeproj` | 1 | Unverified: requires full Xcode, but active developer directory is Command Line Tools. |
| `xcodebuild -project LiveOverlayTranslator.xcodeproj -scheme LiveOverlayTranslator -configuration Debug -derivedDataPath /tmp/LiveOverlayTranslatorDerivedData CODE_SIGNING_ALLOWED=NO build` | 1 | Unverified for same full-Xcode requirement. |
| `rg -n <legacy Clean Share safety label> README.md docs macos/LiveOverlayTranslator/Sources` | 1 | No remaining user-visible share-safety claim text found. |

Backend automated tests: 9 test files, 30 tests, passing.

Swift tests present: 7 Swift test files, 16 `@Test` cases. They did not execute because the installed Command Line Tools cannot import Swift Testing's `Testing` module.

Xcode build: unverified. `xcodebuild` cannot run until full Xcode is installed and selected.

## Manual Physical Mac Steps

1. Select full Xcode:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. Start backend mock:

   ```bash
   cd /Users/roman/Documents/speech_to_text_2.0/server
   cp ../.env.example .env
   npm run dev
   ```

3. Launch the macOS app from Xcode.
4. Run Local Mock mode and verify delayed provisional/final/result UI.
5. Switch to Backend mode with `ws://127.0.0.1:8787/ws`.
6. Click Start Listening, grant microphone permission, speak one phrase, and verify bounded frames plus one commit.
7. For real OpenAI, set backend-only `OPENAI_API_KEY` in `server/.env`, set `MOCK_OPENAI=false`, restart backend, then repeat microphone flow.
8. Confirm Stop Listening does not display a false disconnect warning.
9. Confirm system audio and Clean Share controls are not exposed and the docs/UI mark them unavailable.

## Current Readiness

| Target | Readiness |
| --- | --- |
| Local Mock demonstration | READY in code; requires GUI run for visual confirmation. |
| Backend Mock microphone flow | READY in code; backend tests pass; physical microphone run still manual. |
| Real OpenAI microphone flow | READY in code path; requires backend secret and physical Mac microphone validation. |
| System audio | NOT READY; explicitly unavailable. |
| Clean Share | NOT READY; explicitly unavailable. |
| Production use | NOT READY; requires WSS deployment, Xcode/manual validation, privacy validation, signing/notarization, and out-of-scope features. |
