# LiveOverlayTranslator Acceptance Report

Report date: 2026-06-18

> Historical note: this report documents the earlier audit commit. It is superseded for P0 microphone readiness by `docs/p0-microphone-report.md`. Current code marks system audio and Clean Share unavailable, and current Swift/Xcode validation remains blocked by the local Command Line Tools/Xcode setup.

## Repository State Before Fixes

- Branch: `main`, tracking `origin/main`.
- Initial audited state had backend tests passing only for 16 cases, Swift package building, but macOS tests blocked by the installed Command Line Tools test framework setup.
- Backend real-mode audio routing sent binary audio and `input_audio_buffer.commit` to every active Realtime client instead of the utterance source.
- Backend did not expose unit-testable WebSocket message limit helpers.
- Realtime transcription delay was hardcoded to `low` rather than configurable with default `low`.
- README used a key-shaped `OPENAI_API_KEY` example placeholder, which triggered secret-pattern searches even though no real secret was present.

## Commands Executed

| Command | Result |
| --- | --- |
| `git status -sb` | PASS: repo was clean before audit changes. |
| `rg --files -g '!server/node_modules/**' -g '!server/dist/**' -g '!macos/LiveOverlayTranslator/.build/**'` | PASS: repository inventory collected. |
| `find . -name '*.xcodeproj' -o -name '*.xcworkspace'` | PASS: found `macos/LiveOverlayTranslator/LiveOverlayTranslator.xcodeproj`. |
| `npm ci` | PASS with warning: installed from `package-lock.json`; npm warned current Node is v23.10.0 while Vitest declares `^20 || ^22 || >=24`. |
| `npm run` | PASS: only `dev`, `start`, `typecheck`, `test`, and `build` scripts exist. No lint/format scripts are defined. |
| `npm run typecheck` | PASS after sequential run. |
| `npm test` | PASS after fixes: 8 files, 23 tests. |
| `npm run build` | PASS. |
| `swift build` | PASS: SwiftPM package and executable target compile. |
| `swift test` | FAIL in this environment: `no such module 'Testing'`. |
| `xcodebuild -list -project LiveOverlayTranslator.xcodeproj -derivedDataPath /tmp/LiveOverlayTranslatorDerivedData` | UNVERIFIED: active developer directory is `/Library/Developer/CommandLineTools`; full Xcode is required. |
| `git check-ignore .env server/.env macos/LiveOverlayTranslator/.build server/node_modules server/dist` | PASS: sensitive/env and build artifacts are ignored. |
| `rg` current-tree secret search | PASS: no current key-shaped values found after README cleanup. |
| `git log --all -p` secret-pattern search | PASS with note: visible history contains an old non-secret README placeholder shaped like an OpenAI key; no real secret value was found. |
| `MOCK_OPENAI=true PORT=8787 node dist/index.js` | PASS: backend listened on `http://127.0.0.1:8787`. |
| `curl --fail --silent http://127.0.0.1:8787/health` | PASS: returned `{"ok":true,"mockOpenAI":true}`. |
| Local WebSocket mock flow | PASS: returned `session_state`, `transcript_delta`, `transcript_completed`, `overlay_result`, one card-equivalent result. |

Note: one early backend validation attempt ran `npm ci` in parallel with `typecheck/test/build`; those transient module-resolution failures were caused by `node_modules` being rewritten during the checks and were discarded. Sequential validation is the accepted evidence.

## Acceptance Matrix

| # | Acceptance item | Status | Evidence | Reason and next action for non-PASS |
| --- | --- | --- | --- | --- |
| 1 | Backend installs successfully. | PASS | `npm ci` exit 0. |  |
| 2 | Backend type checking passes. | PASS | `npm run typecheck` exit 0. |  |
| 3 | Backend unit tests pass. | PASS | `npm test`: 8 files, 23 tests. |  |
| 4 | Backend production build passes. | PASS | `npm run build` exit 0. |  |
| 5 | macOS project can be discovered by xcodebuild. | UNVERIFIED | `xcodebuild -list ...` could not run. | Full Xcode is not selected; active developer directory is Command Line Tools. Next: install/select Xcode with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, then rerun the command with `/tmp` DerivedData. |
| 6 | macOS application target compiles. | PARTIAL | `swift build` exit 0. | SwiftPM executable target compiles. Xcode app target was not verified because `xcodebuild` requires full Xcode. Next: run Xcode build on physical Mac. |
| 7 | macOS unit tests pass. | FAIL | `swift test` exit 1. | Tests cannot compile in this CLT setup: `no such module 'Testing'`. Files exist under `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests`. Next: rerun with full Xcode/valid Swift Testing toolchain, or convert tests to the available test framework. |
| 8 | Mock mode works without OPENAI_API_KEY. | PASS | Backend mock tests and prior WebSocket mock flow; `MOCK_OPENAI=true` uses `MockOpenAIResponsesClient`. |  |
| 9 | Mock transcript deltas appear in OverlayState. | PARTIAL | Implementation in `OverlayState.apply(.transcriptDelta)` and Swift test `MockEndToEndTests.swift`. | Automated Swift test could not run in current toolchain. Next: run `swift test` under full Xcode. |
| 10 | Mock transcript completion triggers exactly one overlay result. | PASS | `ClientSessionManager` mock flow test passes; dedupe tests pass. |  |
| 11 | Duplicate completion events are ignored. | PASS | `RealtimeEventRouter` duplicate completion test passes. |  |
| 12 | Out-of-order results do not overwrite newer utterances. | PARTIAL | `OverlayStateTests.swift` covers stale result protection. | Swift tests could not run here. Backend item correlation tests pass for out-of-order OpenAI completions. Next: verify Swift tests under full Xcode. |
| 13 | Suggested replies are not automatically added to spoken dialogue context. | PASS | Backend `DialogueContextService` test passes. Swift `DialogueStoreTests.swift` exists but was not executable here. |  |
| 14 | Microphone capture is implemented. | PARTIAL | `MicrophoneAudioCaptureService.swift` uses `AVAudioEngine`, permission request, tap install/removal, PCM conversion. | Not runtime-verified with macOS permission/device. Next: manual microphone permission and transcription tests. |
| 15 | PCM output is mono, signed 16-bit little-endian, 24 kHz. | PARTIAL | `SimplePCMResampler` converts Float32 to mono 24 kHz Int16; `AudioStreamCoordinator` writes little-endian Int16 data. | Swift test coverage exists but could not run. Next: run Swift tests and add golden PCM fixture if needed. |
| 16 | Speech endpoint detection is implemented. | PARTIAL | `EnergySpeechEndpointDetector` implements configurable energy endpointing. | Swift tests for endpointing could not run here. Next: run on full Xcode toolchain and tune with real audio. |
| 17 | Pre-roll is preserved. | PARTIAL | Detector keeps pre-roll buffer; Swift test exists. | Test could not run in this environment. Next: run Swift tests under full Xcode. |
| 18 | Manual input_audio_buffer.commit is implemented. | PASS | `OpenAIRealtimeTranscriptionClient.commit()` sends `input_audio_buffer.commit`; server calls commit only for the utterance source after fix. |  |
| 19 | gpt-realtime-whisper transcript events are parsed. | PASS | `RealtimeEventRouter` handles delta/completed event types and tests pass. |  |
| 20 | Responses API Structured Output parsing is implemented. | PASS | `OpenAIResponsesClient` uses `client.responses.parse` with `zodTextFormat`; `OverlayResponseService` validates with Zod. |  |
| 21 | OPENAI_API_KEY is absent from the macOS source and bundle configuration. | PASS | `rg` in `macos` found no key/API-key references. |  |
| 22 | System audio capture is implemented. | FAIL | Superseded P0 behavior: `SystemAudioCaptureService.start` now returns unavailable. | Future work requires real `SCStream`, audio output handling, PCM conversion, and callback delivery. |
| 23 | Local and remote streams remain logically separate. | FAIL | Superseded P0 behavior: the backend rejects overlapping active utterances and the app exposes microphone only. | True simultaneous overlap needs a protocol change because binary frames are untagged. |
| 24 | Overlay is implemented as a real translucent NSPanel. | PASS | `OverlayWindowController.swift` creates transparent non-opaque `NSPanel` with SwiftUI content. |  |
| 25 | Overlay can join Spaces and full-screen auxiliary contexts. | PASS | `panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. |  |
| 26 | Emergency hide shortcut is implemented. | PARTIAL | `GlobalShortcutController` has Ctrl-Option-H path and AppDelegate hides overlay/Clean Share. | Runtime global shortcut reliability and permissions are unverified. Next: manual shortcut test while another app is focused. |
| 27 | Clean Share uses ScreenCaptureKit. | FAIL | Superseded P0 behavior: `CleanShareCoordinator.start` returns unavailable. | Future work must implement `SCContentFilter`, `SCStream`, output rendering, and lifecycle cleanup. |
| 28 | Clean Share excludes all application-owned windows. | FAIL | No running Clean Share stream exists in P0. | Implement and verify real self-window exclusion in a future task. |
| 29 | Clean Feed avoids recursive capture. | FAIL | No running Clean Share stream exists in P0. | Implement and verify real clean-feed rendering in a future task. |
| 30 | README contains reproducible setup and run instructions. | PASS | README contains backend setup, commands, macOS setup, permissions, mock flow, limitations. |  |

## Defects Found And Fixed

1. Backend real-mode audio routing sent audio and commits to every Realtime session.
   - Fixed in `server/src/ws/ClientSessionManager.ts`.
   - Added test in `server/tests/clientSessionManager.test.ts`.

2. WebSocket size limits were not exposed to unit tests.
   - Added `server/src/ws/messageLimits.ts`.
   - Added `server/tests/messageLimits.test.ts`.

3. Realtime disconnect handling had no session-manager surface.
   - Added `handleRealtimeDisconnect`.
   - Wired `OpenAIRealtimeTranscriptionClient` `close` event to server manager.

4. Realtime transcription delay was hardcoded.
   - Added `OPENAI_REALTIME_DELAY`, default `low`.

5. README used an `sk-...` placeholder.
   - Replaced with `<your-openai-api-key>`.

## Defects Still Open

- macOS test execution is blocked in this environment by missing Swift Testing module support.
- `xcodebuild` discovery/build is blocked until full Xcode is installed and selected.
- System audio capture is unavailable in the P0 microphone build.
- Clean Share is unavailable in the P0 microphone build.
- True simultaneous local and remote audio overlap is unsupported by the current single active binary-frame routing model.
- WebSocket reconnect, sleep/wake recovery, audio-device disconnect recovery, and permission-denied UX need physical Mac verification and additional implementation.

## Security Review

- No real OpenAI key or private key was found in current source or visible `.env` history.
- Visible Git history contains an old non-secret README placeholder shaped like an OpenAI key. Current working tree no longer contains that pattern. Rewrite pushed history only if repository policy forbids key-shaped placeholders in history.
- `.env`, `server/.env`, build outputs, and dependency folders are ignored.
- `OPENAI_API_KEY` is loaded only in backend config.
- macOS source and plist files do not contain `OPENAI_API_KEY` or key-like strings.
- Log redaction covers transcript fields, audio payload fields, and API key/header fields.
- WebSocket JSON and audio frame sizes are bounded.
- Dialogue context is bounded to 10 turns in the session manager and max 12 in the final envelope schema.
- Responses API calls set `store: false`.
- Production WSS/TLS is documented but not enforced by code; deploy behind TLS/WSS reverse proxy before any production use.

## OpenAI Boundary Review

- Realtime append uses `input_audio_buffer.append` with base64 PCM16.
- Realtime session config sets transcription model to the configured `OPENAI_REALTIME_MODEL`, default `gpt-realtime-whisper`.
- Realtime turn detection is `null`.
- No prompt is sent to Realtime transcription.
- `input_audio_buffer.commit` is manual and now routed to the utterance source.
- Transcript deltas do not call Responses.
- Completed transcript events route through item ID correlation and trigger deduped Responses calls.
- Responses model defaults to `gpt-5.4-mini` through backend env configuration.
- Structured Output parsing uses OpenAI SDK `zodTextFormat` plus Zod validation.

## Clean Share Review

Current P0 implementation is unavailable by design. It does not create an `SCContentFilter`, start an `SCStream`, render frames, or prove recursive/self-window exclusion. The user must not rely on LiveOverlayTranslator to hide the overlay from screen sharing.

## Readiness

| Target | Readiness |
| --- | --- |
| Mock demonstration | PARTIAL: backend mock path is verified; macOS app compiles but mock UI behavior needs runtime GUI check. |
| Real microphone testing | PARTIAL: capture code exists and package compiles; requires physical Mac permission test and real backend. |
| Real system audio testing | NOT READY: system audio is explicitly unavailable in P0. |
| Clean Share testing | NOT READY: Clean Share is explicitly unavailable in P0. |
| Production use | NOT READY: macOS runtime behavior, Clean Share, system audio, reconnect, sleep/wake, and manual privacy behavior are unverified/incomplete. |

## Next Command For A Physical Mac

After installing/selecting full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cd /Users/roman/Documents/speech_to_text_2.0/macos/LiveOverlayTranslator
xcodebuild -list -project LiveOverlayTranslator.xcodeproj -derivedDataPath /tmp/LiveOverlayTranslatorDerivedData
swift test
swift build
```

Then run the manual checklist in `docs/manual-macos-test-checklist.md`.
