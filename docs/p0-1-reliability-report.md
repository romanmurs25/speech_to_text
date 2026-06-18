# P0.1 Microphone Reliability Report

Report date: 2026-06-18

## Initial State

- Required base commit: `32917d48b2760be50759026ff6dc0abd1de5894f`.
- Actual HEAD at start: `32917d4 Implement P0 microphone vertical slice`.
- Branch: `main`, tracking `origin/main`.
- Working tree at start: clean.

## Baseline Commands

| Command | Exit | Result |
| --- | ---: | --- |
| `git status -sb` | 0 | `## main...origin/main` |
| `git log --oneline --decorate -5` | 0 | HEAD is `32917d4`; previous commits are `8782133`, `1cedd54`. |
| `git show --stat --oneline HEAD` | 0 | Confirmed P0 microphone vertical slice commit. |
| `git diff --check` | 0 | No whitespace errors before editing. |

## Defects Confirmed

- The first targeted backend RED run failed as expected: protocol validation did not know `utterance_cancel`, session cancellation did not clear/skip commits, duplicate commit handling was unsafe, overlap was recoverable instead of fail-closed, Realtime `clear` did not exist, queue overflow could be revived, and real mode without an API key did not fail at app creation.
- Existing correlation/router unit tests assumed `markCommitted()` could correlate any enqueued utterance. The new lifecycle requires explicit `requestCommit()` before OpenAI commit acknowledgement.
- macOS cleanup paths could leave stale capture/processing tasks around generation changes, and short utterance discard used stop/start semantics instead of cancellation.
- Local Mock P0 implied a reply was needed for local microphone speech; the requirement is `microphone/local`, `reply_needed=false`, and empty suggestions.

## Work Performed

- Added cross-platform `utterance_cancel` protocol support with controlled reasons: `minimum_speech_duration_not_met`, `audio_pipeline_overflow`, `capture_interrupted`, `user_interrupted`, and `application_shutdown`.
- Reworked `UtteranceCorrelationStore` around an explicit lifecycle: `active`, `commitRequested`, `correlated`, `completed`, and `cancelled`, with duplicate start/commit handling and bounded finished records.
- Added backend cancellation behavior: active utterance cancellation clears OpenAI Realtime input with `input_audio_buffer.clear`, avoids commit/transcript/result generation, and keeps later valid utterances working.
- Hardened Realtime client behavior: `clear()`, `input_audio_buffer.cleared` handling, bounded event/audio readiness queues, terminal overflow, ignored late `session.updated`, and single terminal failure callback for socket error/close paths.
- Changed ambiguous overlapping utterances to fatal `ambiguous_audio_routing`; the backend clears pending Realtime input, terminates the WebSocket, and ignores following audio.
- Made real backend mode fail before listening when `MOCK_OPENAI=false` and `OPENAI_API_KEY` is absent.
- Made macOS capture cleanup idempotent with a session generation guard, bounded audio pipe overflow handling, active utterance cancellation on discard/user stop/capture interruption, and guaranteed disconnect during stop cleanup.
- Preserved detector pre-roll across utterances where appropriate so the next utterance can include bounded leading context.
- Cleaned overlay pending state on recoverable translation errors, fatal errors, and closed sessions.
- Updated Local Mock and backend mock behavior to be truthful for local microphone speech: real Russian translation text, no reply needed, and empty suggested replies.
- Updated protocol, architecture, README, manual checklist, and this report for P0.1 reliability semantics.

## Validation

| Command | Exit | Result |
| --- | ---: | --- |
| `npm test -- tests/protocol.test.ts tests/clientSessionManager.test.ts tests/openAIRealtimeClient.test.ts tests/serverConfig.test.ts` | 1 | Initial RED run failed 8 targeted tests before implementation. |
| `npm test -- tests/protocol.test.ts tests/clientSessionManager.test.ts tests/openAIRealtimeClient.test.ts tests/serverConfig.test.ts` | 0 | Targeted backend reliability suite passed: 4 files, 21 tests. |
| `npm run typecheck` | 0 | TypeScript typecheck passed. |
| `npm test` | 0 | Full backend suite passed: 10 files, 37 tests. |
| `npm run build` | 0 | Backend production TypeScript build passed. |
| `env CLANG_MODULE_CACHE_PATH=/private/tmp/liveoverlay-clang-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/liveoverlay-swift-cache swift build` | 1 | Sandbox-run SwiftPM failed before compiling code with `sandbox-exec: sandbox_apply: Operation not permitted`. |
| same `swift build`, rerun outside sandbox | 0 | macOS Swift package build passed. |
| same environment with `swift test` | 1 | Blocked by active Command Line Tools toolchain: `no such module 'Testing'`. |
| `xcodebuild -list -project macos/LiveOverlayTranslator/LiveOverlayTranslator.xcodeproj` | 1 | Blocked: `xcodebuild` requires full Xcode, active developer directory is Command Line Tools. |
| `xcodebuild -project macos/LiveOverlayTranslator/LiveOverlayTranslator.xcodeproj -scheme LiveOverlayTranslator -configuration Debug -derivedDataPath /private/tmp/liveoverlay-derived build` | 1 | Same full-Xcode environment blocker. |
| `git diff --check` | 0 | No whitespace errors. |
| secret/claim scan with `rg` | 1 | No OpenAI key patterns or unsafe Clean Share/system-audio claims found. |

## Current Readiness

- Backend P0.1 reliability checks are green in automated tests.
- macOS application code compiles with `swift build`.
- Swift unit tests are still blocked by the local Command Line Tools toolchain lacking the Swift `Testing` module; full Xcode is required to validate the Xcode project and run native tests in this workspace.
- Manual microphone validation on a physical Mac with full Xcode, microphone permission, and a live backend is still required before calling this production-ready.
