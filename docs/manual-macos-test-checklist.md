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
3. Confirm only one recoverable error is shown.
4. Confirm the interrupted utterance is not replayed, committed, or translated.
5. Confirm a new user-started session can reconnect.

Expected result: Realtime failures are terminal for the current Realtime client and late readiness events do not revive it.

## 4C. Ambiguous Audio Routing Negative Test

1. Use a protocol harness or backend unit test to send a second `utterance_start` with a different `client_utterance_id` while another utterance is active.
2. Send binary audio after the second start.

Expected result: backend emits fatal `ambiguous_audio_routing`, clears the input buffer when present, terminates the WebSocket, and ignores following audio.

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
6. Confirm uncertain audio is not replayed automatically after reconnect.

Expected result: interrupted utterances are marked interrupted or recoverable; no duplicate transcription request is created.

## 10. Audio Device Disconnect

1. Select an external microphone.
2. Start microphone capture.
3. Disconnect the device during capture.
4. Confirm the app reports a recoverable audio-device error and removes audio taps.
5. Reconnect or select another device.
6. Confirm capture can restart cleanly.

Expected result: no crash, no stale audio tap, no duplicate active capture session.
