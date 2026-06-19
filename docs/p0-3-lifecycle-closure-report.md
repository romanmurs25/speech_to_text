# P0.3 Lifecycle Closure Report

Report date: 2026-06-19

## Initial State

- Required base commit: `c5ea64196939efaf36827e2b302bd7088df582b5`.
- Initial `HEAD`: `c5ea64196939efaf36827e2b302bd7088df582b5`.
- Initial branch state: `main...origin/main`, clean working tree.
- Initial `git diff --check`: pass.
- No previous commits were amended, squashed, rebased, or rewritten.

## Confirmed Defects

- Local Mock natural completion left the mock task/context non-nil, disabling restart.
- Local Mock had no generation guard against stale async events.
- `session_state.closed` changed UI state without cleaning the active backend microphone session.
- Audio overflow and `utterance_commit` admission were separated by await boundaries.
- Client WebSocket close did not terminalize backend session work.
- In-flight Responses requests were ignored after termination but not aborted.
- App termination used a structured task group that could wait for hung cleanup.
- Accepted client WebSockets had no explicit `error` lifecycle wrapper.
- OpenAI Realtime terminal callback could cause a second underlying socket close.
- `BoundedAudioChunkPipe` called `AsyncStream` continuation methods while holding its lock.

## Local Mock Lifecycle Design

`ApplicationController` now owns a generation-bound `LocalMockRunContext` with an invalidation token and task reference. Natural completion clears the current context only if it is still current. Stop and application termination invalidate and cancel the exact context. `MockOverlayEventSource` checks cancellation after every delay so cancelled mock runs cannot emit final stale events.

## Remote Close Cleanup Design

`session_state.closed` is terminal for the exact active `BackendMicrophoneSessionContext`. The app now schedules normal cleanup for that context: invalidate token, stop microphone immediately, invalidate pipe, cancel receive/processing tasks, cancel/disconnect coordinator/client, clear `currentSession`, and end failed/interrupted. Duplicate cleanup reuses the context cleanup task; stale contexts are ignored by generation/current checks.

## Commit Arbitration State Diagram

```text
open
  | invalidate(reason) before admission
  v
invalidated(reason) -> no commit, pre-commit cancel allowed

open
  | tryAdmitCommit()
  v
commitAdmitted
  | markCommitSendStarted()
  v
commitSendStarted
  | markCommitSendCompleted()
  v
commitSendCompleted
  | finish()
  v
finished

commitAdmitted/commitSendStarted/commitSendCompleted
  | invalidate(reason)
  v
commitAdmittedThenInvalidated(reason) -> no false cancel claim; unfinished result is abandoned/uncertain
```

`AudioStreamCoordinator` uses explicit utterance lifecycle states: `idle`, `active`, `cancelling`, `commitAdmitted`, `commitInFlight`, `committed`, and `finished`. Frames are sent only while active. Cancel is sent only for active pre-commit utterances. Once commit admission wins, later invalidation terminates without sending a false `utterance_cancel`.

## Backend Terminalization Design

`ClientSessionManager.close()` now sets both closed and terminal state, aborts Responses work, clears unfinished correlations, closes Realtime clients, clears active utterance state, and prevents future control/audio/Realtime handling. Fatal Realtime failures and ambiguous routing share the same terminalization path. Critical send failure for `session_state.ready`, `transcript_completed`, or `overlay_result` terminalizes the session so backend work does not continue for a gone client.

`SafeClientWebSocketSession` wraps accepted client sockets with safe send, safe close, `error` handling, and exactly-once manager closure. A client socket error logs a redacted warning, closes the manager once, and closes the socket safely without throwing.

## Responses Cancellation Design

Each `ClientSessionManager` owns one `AbortController`. `OverlayResponseService.translate` and `OpenAIResponsesClient.createOverlayResult` accept `{ signal }`. The OpenAI Responses request combines the session signal with the per-request timeout. Client close, fatal termination, ambiguous routing, and Realtime terminal failure abort the signal. Aborted requests map to internal `request_aborted`, are removed from `inFlight`, are not cached as completed results, and do not produce late overlay results or translation errors after session termination.

## Application Termination Deadline Design

`prepareForTermination()` still stops microphone capture and invalidates the pipe synchronously before returning `terminateLater`. `AppDelegate.applicationShouldTerminate` now starts one unstructured cleanup task and one unstructured timeout task. Both race through `TerminationReplyGate`, so `reply(toApplicationShouldTerminate:)` happens exactly once. If timeout wins, cleanup is cancelled and macOS receives the reply at the deadline.

## Files Changed

- `README.md`
- `docs/architecture.md`
- `docs/manual-macos-test-checklist.md`
- `docs/protocol.md`
- `docs/p0-3-lifecycle-closure-report.md`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/ApplicationController.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/LiveOverlayTranslatorApp.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/AudioStreamCoordinator.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/BoundedAudioChunkPipe.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/MockOverlayEventSource.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/SessionCommitArbiter.swift`
- `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslatorCore/TerminationReplyGate.swift`
- `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/SessionCommitArbiterTests.swift`
- `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/TerminationReplyGateTests.swift`
- `server/src/openai/OpenAIRealtimeTranscriptionClient.ts`
- `server/src/openai/OpenAIResponsesClient.ts`
- `server/src/server.ts`
- `server/src/services/OverlayResponseService.ts`
- `server/src/services/RequestDeduplicator.ts`
- `server/src/ws/ClientSessionManager.ts`
- `server/src/ws/safeWebSocket.ts`
- `server/tests/clientSessionManager.test.ts`
- `server/tests/openAIRealtimeClient.test.ts`
- `server/tests/overlayResponse.test.ts`
- `server/tests/safeWebSocket.test.ts`

## Tests Added

- Backend `ClientSessionManager` tests for close terminal state, close/fatal abort during Responses, and critical send failure terminalization.
- Backend `OverlayResponseService` tests for abort-signal propagation and no completed-cache entry after abort.
- Backend `OpenAIRealtimeTranscriptionClient` tests for exactly-once underlying socket close.
- Backend `SafeClientWebSocketSession` tests for error plus close idempotency and send suppression after close begins.
- Swift `SessionCommitArbiterTests` for pre-admission invalidation, one commit admission, post-admission invalidation, send boundary, and finish.
- Swift `TerminationReplyGateTests` for cleanup-first and timeout-first exactly-once replies.

## Commands Executed

| Command | Exit | Result |
| --- | ---: | --- |
| `git status -sb` | 0 | Initial clean `main...origin/main`. |
| `git rev-parse HEAD` | 0 | `c5ea64196939efaf36827e2b302bd7088df582b5`. |
| `git log --oneline --decorate -10` | 0 | Confirmed P0.2 HEAD and prior history. |
| `git show --stat --oneline HEAD` | 0 | Captured P0.2 commit summary. |
| `git diff --check` | 0 | Initial whitespace check passed. |
| `npm test` after RED tests | 1 | Expected RED: 9 failed, 52 passed. |
| `npm test` after backend implementation | 0 | 11 files, 61 tests passed. |
| `npm run typecheck` | 0 | Source and test TypeScript passed. |
| `npm run build` | 0 | Backend production TypeScript build passed. |
| `swift build` in sandbox | 1 | Blocked before compile by `sandbox-exec: Operation not permitted`. |
| `swift build` escalated | 0 | Swift package and executable target compiled. |
| `swift test` escalated | 1 | Blocked by local toolchain: `no such module 'Testing'`. Executed Swift tests: 0. |
| `npm ci` | 0 | Installed 106 packages; npm warned Node v23.10.0 is outside Vitest engine range `^20 || ^22 || >=24`. |
| `npm run typecheck` after `npm ci` | 0 | Source and test TypeScript passed. |
| `npm test` after `npm ci` | 0 | 11 files, 61 tests passed. |
| `npm run build` after `npm ci` | 0 | Backend build passed. |
| `swift build` final escalated | 0 | Swift build passed. |
| `swift test` final escalated | 1 | Blocked by `no such module 'Testing'`. Executed Swift tests: 0. |
| `xcodebuild -list -project LiveOverlayTranslator.xcodeproj` | 1 | Blocked: active developer directory is `/Library/Developer/CommandLineTools`, not full Xcode. |
| `xcodebuild -project LiveOverlayTranslator.xcodeproj -scheme LiveOverlayTranslator -configuration Debug -derivedDataPath /tmp/LiveOverlayTranslatorDerivedData CODE_SIGNING_ALLOWED=NO build` | 1 | Same full-Xcode limitation. |
| `git diff --stat` | 0 | Captured final diff summary before report. |
| `git diff --name-only` | 0 | Captured tracked changed files before report. |
| `git diff --check` | 0 | Final whitespace check passed before report. |

## Validation Summary

- Backend test count: 61 passing Vitest tests across 11 files.
- TypeScript source typecheck: PASS.
- TypeScript test typecheck: PASS.
- Backend build: PASS.
- Swift test target: `LiveOverlayTranslatorTests`, 12 Swift test files, 33 `@Test` declarations.
- Executed Swift test count: 0, because local Command Line Tools cannot import Swift `Testing`.
- Swift build: PASS.
- Xcode build: UNVERIFIED, blocked by selected Command Line Tools instead of full Xcode.
- Physical Mac microphone/GUI tests performed: none in this environment.

## Remaining Limitations

- Swift tests are added but not executable in this local toolchain until Swift `Testing` is available.
- Full Xcode project discovery/build is unverified until `xcode-select` points at full Xcode.
- Physical microphone capture, AVAudioEngine tap removal, permission-prompt races, app termination timing, and UI restart flows still require manual validation on a physical Mac.
- Automatic reconnect remains unimplemented.
- System audio remains unavailable.
- Clean Share remains unavailable.
- Production use remains not ready.

## Readiness

| Area | Status |
| --- | --- |
| Local Mock | READY for local code path; physical GUI repeat test still recommended. |
| Backend Mock microphone | PARTIAL: backend tests/build pass and Swift build passes; physical microphone run still required. |
| Real OpenAI microphone | NOT READY for readiness claim until physical Mac test with a real backend key passes. |
| System audio | NOT READY; explicitly unavailable. |
| Clean Share | NOT READY; explicitly unavailable. |
| Production use | NOT READY. |

## Next Physical-Mac Command

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cd /Users/roman/Documents/speech_to_text_2.0/macos/LiveOverlayTranslator
xcodebuild -list -project LiveOverlayTranslator.xcodeproj
xcodebuild -project LiveOverlayTranslator.xcodeproj -scheme LiveOverlayTranslator -configuration Debug -derivedDataPath /tmp/LiveOverlayTranslatorDerivedData CODE_SIGNING_ALLOWED=NO build
swift test
```

Then run `docs/manual-macos-test-checklist.md`, especially sections 4J through 4P.
