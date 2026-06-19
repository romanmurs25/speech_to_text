# Manual macOS Test Checklist

Use a physical Mac with full Xcode selected by `xcode-select`, a development build, microphone permission, and a running backend. Record macOS version, Xcode version, app build SHA, backend SHA, backend URL, and whether `MOCK_OPENAI` is true or false.

## 1. Local Mock

1. Launch the app.
2. Select `Local Mock`.
3. Click `Start Listening`.
4. Confirm the overlay shows provisional text first.
5. Confirm a finalized transcript card appears.
6. Confirm pending translation is visible before the result.
7. Confirm Russian and English translations appear and suggested replies are empty for the local microphone mock.
8. Click `Stop Listening`.

Expected result: one deterministic microphone/local mock card appears; no backend connection, microphone permission, or API key is required.

## 2. Microphone Permission

1. Remove any existing microphone permission for LiveOverlayTranslator in System Settings.
2. Launch the app.
3. Select `Backend`.
4. Click `Start Listening`.
5. Confirm macOS prompts for microphone access.
6. Deny access.
7. Confirm the app shows a non-intrusive microphone permission denied state and does not crash.
8. Grant access in System Settings.
9. Restart the app and confirm microphone capture can start.

Expected result: permission denial is handled; granted permission allows capture.

## 3. Backend Mock Microphone

1. Start backend with `MOCK_OPENAI=true`.
2. Launch the app.
3. Select `Backend`.
4. Set backend URL to `ws://127.0.0.1:8787/ws`.
5. Click `Start Listening`.
6. Speak one short utterance.
7. Stop speaking and wait for local endpoint detection.
8. Confirm the backend receives multiple small binary frames, not one full-utterance frame.
9. Confirm exactly one commit is sent for the accepted utterance.
10. Confirm the mock transcript and overlay result reach the overlay.

Expected result: local speech is labeled `local`; exactly one final card is created.

## 3A. Short Utterance Cancellation

1. Start backend with `MOCK_OPENAI=true` or `MOCK_OPENAI=false`.
2. Start Backend microphone mode in the app.
3. Make a very short click, cough, or clipped syllable shorter than the minimum speech duration.
4. Confirm no transcript card or pending translation remains for that discarded sound.
5. Speak a normal phrase immediately afterward.
6. Confirm the normal phrase creates exactly one final card.

Expected result: the app sends `utterance_cancel` with `minimum_speech_duration_not_met`; the backend does not commit or translate the discarded utterance.

## 3B. Stop And Interrupt Cleanup

1. Start Backend microphone mode.
2. Begin speaking a phrase.
3. Click `Stop Listening` before endpoint detection commits it.
4. Confirm microphone capture stops, the WebSocket disconnects, and pending overlay translation state is cleared.
5. Start listening again and speak a normal phrase.

Expected result: user stop cancels the active utterance, clears the Realtime input buffer, disconnects cleanly even if stop control delivery fails, and the next session starts fresh.

## 4. Real OpenAI Microphone

1. Start backend with `MOCK_OPENAI=false` and a valid backend-only `OPENAI_API_KEY`.
2. Launch the app.
3. Select `Backend`.
4. Click `Start Listening`.
5. Speak one English phrase.
6. Confirm provisional text appears only as transcript deltas.
7. Stop speaking and wait for final transcript.
8. Confirm translation generation starts only after the completed transcript.
9. Confirm Russian and English translations render.
10. Click `Stop Listening`.
11. Confirm normal stop does not show a false disconnect warning.

Expected result: real microphone transcription and translation work through the backend; the key remains backend-only.

## 4A. Real Mode Missing API Key

1. Start backend with `MOCK_OPENAI=false` and no `OPENAI_API_KEY`.
2. Confirm the backend fails during startup before accepting microphone sessions.

Expected result: real mode refuses to listen without a backend-only OpenAI API key.

## 4B. Realtime Disconnect Or Overflow

1. Start Backend microphone mode against a real or instrumented backend.
2. Force a Realtime socket close, Realtime error, or readiness queue overflow.
3. Confirm the backend emits a terminal `fatal_error` for the current session.
4. Confirm the interrupted utterance is not replayed, committed, or translated.
5. Confirm microphone capture stops and the client WebSocket closes.
6. Confirm a new session starts only after the user explicitly clicks `Start Listening` again.

Expected result: Realtime failures are terminal for the current session and late readiness events do not revive it.

## 4C. Ambiguous Audio Routing Negative Test

1. Use a protocol harness or backend unit test to send a second `utterance_start` with a different `client_utterance_id` while another utterance is active.
2. Send binary audio after the second start.

Expected result: backend emits fatal `ambiguous_audio_routing`, clears the input buffer when present, terminates the WebSocket, and ignores following audio.

## 4D. Stop During Permission Prompt

1. Select `Backend` mode.
2. Click `Start Listening`.
3. While the macOS microphone prompt is open, click `Stop Listening` if possible or trigger session cancellation through a test harness.
4. Grant permission afterward.
5. Verify microphone capture does not start.
6. Verify the UI remains stopped.

Expected result: Stop invalidates the startup session before the input tap is installed.

## 4E. Backend Failure During Permission Prompt

1. Start `Backend` mode.
2. Leave the microphone permission prompt open.
3. Stop the backend.
4. Grant microphone permission.
5. Verify the app does not install a tap or enter listening.

Expected result: backend failure invalidates the session, cleanup completes, and stale permission completion cannot start capture.

## 4F. Realtime Terminal Failure Cleanup

1. Begin listening.
2. Force the backend Realtime connection to fail.
3. Verify the microphone indicator stops.
4. Verify the AVAudioEngine tap is removed.
5. Verify the app enters failed/interrupted.
6. Verify Start becomes available only after cleanup.
7. Verify a new explicitly started session works.

Expected result: the exact failed session context is cleaned up and no stale receive or processing task updates a later session.

## 4G. Audio Pipeline Overflow

1. Use a development setting or test harness with an intentionally tiny audio pipe.
2. Cause overflow.
3. Verify one visible overflow error.
4. Verify the current utterance is cancelled.
5. Verify no final transcript appears.
6. Verify no commit appears in backend diagnostics.
7. Verify microphone stops.
8. Verify the user must explicitly restart.

Expected result: overflow invalidates synchronously, no `utterance_commit` is sent after overflow, and cleanup stops capture.

## 4H. Rapid Start/Stop Ownership

Run 20 cycles:

1. Click `Start Listening`.
2. Click `Stop Listening` immediately.
3. Start again after cleanup.

Expected result: one AVAudioEngine tap at a time, one WebSocket at a time, no stale callbacks, no increasing duplicate messages, and no session A cleanup affecting session B.

## 4I. Stop During Speech

1. Begin a phrase.
2. Click `Stop Listening` before endpoint completion.
3. Verify one `utterance_cancel`.
4. Verify one `input_audio_buffer.clear`.
5. Verify zero commit.
6. Verify one Realtime close.
7. Verify no late transcript.

Expected result: normal user stop is idempotent and does not double-clear Realtime input.

## 4J. Repeat Local Mock Then Backend

1. Select `Local Mock`.
2. Run Local Mock ten times.
3. After every run, verify Start becomes available again.
4. Verify no stale transcript or overlay event appears from a previous run.
5. Switch to `Backend`.
6. Start Backend microphone mode.

Expected result: every Local Mock run completes, its task/context is cleared, Backend starts without app restart, and Local Mock never requests microphone or backend access.

## 4K. Backend Remote Close While Listening

1. Start Backend microphone mode.
2. Begin speaking.
3. Make the backend send `session_state.closed` and close the socket.
4. Verify the microphone indicator stops immediately.
5. Verify the AVAudioEngine tap is removed.
6. Verify the app enters failed/interrupted state.
7. Verify an explicit new Start creates a fresh session.

Expected result: remote close cleans up the exact active backend context, clears current session ownership, and does not leave microphone capture running.

## 4L. Backend Remote Close During Permission Prompt

1. Remove microphone permission for the app.
2. Start Backend mode.
3. Leave the macOS microphone permission prompt open.
4. Make the backend close the session.
5. Grant microphone permission.

Expected result: the stale permission success cannot install an input tap or enter listening.

## 4M. Overflow Before Commit Admission

1. Use a development build or harness with a tiny bounded audio pipe.
2. Trigger audio-pipe overflow before endpoint completion.
3. Inspect backend diagnostics.

Expected result: zero `utterance_commit`, one pre-commit cancellation, microphone stops, and user must explicitly restart.

## 4N. Overflow After Commit Admission

1. Use a debug transport that suspends commit send after local admission.
2. Trigger audio-pipe overflow while commit is admitted or in flight.
3. Inspect backend and app diagnostics.

Expected result: the app does not claim successful cancellation for a post-admission commit. The session terminates, unfinished output is abandoned/uncertain, and audio is not replayed.

## 4O. Client WebSocket Error

1. Connect one client to the backend.
2. Inject a client WebSocket `error`.
3. Verify the backend process remains running.
4. Verify only that session is closed.
5. Connect a second client.

Expected result: the error is logged safely, `ClientSessionManager.close()` runs exactly once, no send is attempted after close begins, and the second client can connect.

## 4P. Application Termination Deadline

1. Start Backend microphone mode.
2. Quit the application while listening.
3. Verify the microphone indicator disappears immediately.
4. Verify the application replies to macOS termination within the configured deadline, even if backend cleanup is hung.

Expected result: microphone stop and pipe invalidation happen before `terminateLater` returns; cleanup and timeout race through a reply-once gate, so macOS receives exactly one termination reply.

## 5. Overlay Behavior

1. Launch app in Local Mock mode.
2. Confirm overlay is translucent and visible above normal windows.
3. Move and resize the overlay.
4. Switch Spaces and full-screen apps.
5. Confirm overlay joins Spaces and behaves as a full-screen auxiliary panel.

Expected result: overlay remains usable and does not steal activation during presentation.

## 6. System Audio Unavailable

1. Confirm there is no user-facing Start System Audio control in the P0 UI.
2. Confirm any internal `SystemAudioCaptureService.start` path returns `systemAudioUnavailable`.
3. Confirm documentation states that system audio is unavailable in P0.

Expected result: system audio is clearly unavailable and cannot silently start.

## 7. Clean Share Unavailable

1. Confirm there is no user-facing Clean Share start control in the P0 UI.
2. Confirm `CleanShareCoordinator.start` returns `featureNotAvailable`.
3. Confirm no UI displays a Clean Share safety indicator.
4. Share the physical Entire Screen source as a negative test only if appropriate.
5. Confirm documentation warns that Entire Screen sharing can expose the overlay.

Expected result: Clean Share is unavailable; the app does not claim it can protect screen sharing.

## 8. Emergency Hide Shortcut

1. Show overlay.
2. Press the configured emergency hide shortcut.
3. Confirm overlay hides immediately.
4. Confirm backend streaming is not left in an unsafe state.

Expected result: windows hide immediately. Verify shortcut reliability while another app is focused.

## 9. Sleep And Wake

1. Start app in Local Mock mode.
2. Put Mac to sleep.
3. Wake Mac.
4. Confirm overlay remains responsive.
5. Repeat with real microphone transcription running.
6. Confirm uncertain audio is not replayed automatically after the user starts a new session.

Expected result: interrupted utterances are marked interrupted or recoverable; no duplicate transcription request is created.

## 10. Audio Device Disconnect

1. Select an external microphone.
2. Start microphone capture.
3. Disconnect the device during capture.
4. Confirm the app reports a recoverable audio-device error and removes audio taps.
5. Reconnect or select another device.
6. Confirm capture can restart cleanly.

Expected result: no crash, no stale audio tap, no duplicate active capture session.
