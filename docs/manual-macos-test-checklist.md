# Manual macOS Test Checklist

Use a physical Mac with full Xcode selected by `xcode-select`, a signed development build, microphone permission, screen-recording permission, and no real meeting running until the Clean Feed checks.

Record macOS version, Xcode version, app build SHA, backend SHA, backend URL, and whether `MOCK_OPENAI` is true or false.

## 1. Microphone Permission

1. Remove any existing permission for LiveOverlayTranslator in System Settings.
2. Launch the app from Xcode.
3. Start microphone listening.
4. Confirm macOS prompts for microphone access.
5. Deny access.
6. Confirm the app shows a non-intrusive microphone permission denied state and does not crash.
7. Grant access in System Settings.
8. Restart the app and confirm microphone capture can start.

Expected result: permission denial is handled; granted permission allows capture.

## 2. Screen-Recording Permission

1. Remove any existing screen-recording permission for LiveOverlayTranslator.
2. Launch the app.
3. Start System Audio or Clean Share.
4. Confirm macOS prompts for screen-recording access or the app explains how to grant it.
5. Deny access.
6. Confirm the app shows a screen-recording permission denied state and does not show SAFE SHARE.
7. Grant access and restart the app.

Expected result: denial is handled; SAFE SHARE appears only after the clean stream is actually running.

## 3. Microphone Transcription

1. Start backend with `MOCK_OPENAI=false` and a valid backend-only `OPENAI_API_KEY`.
2. Launch the app and select microphone.
3. Speak one short utterance.
4. Confirm provisional text appears only during the utterance.
5. Stop speaking and wait for final transcript.
6. Confirm translation generation starts only after the final transcript.

Expected result: local speech is labeled `local`; exactly one final card is created.

## 4. System Audio Transcription

1. Start backend with `MOCK_OPENAI=false`.
2. Play remote audio from another application.
3. Select system audio in the app.
4. Confirm screen-recording permission is granted.
5. Confirm remote speech is transcribed and labeled `remote`.

Expected result: system audio is captured independently from microphone audio.

## 5. Simultaneous Local And Remote Audio

1. Select both microphone and system audio.
2. Play remote speech while speaking locally.
3. Confirm the app creates separate local and remote streams.
4. Confirm timestamps and sequence numbers order finalized cards.
5. Confirm overlapping speech is not mixed into one transcript item.

Expected result: local and remote speech remain separate. Current implementation needs additional work before this can pass.

## 6. Overlay Behavior

1. Launch app in mock mode.
2. Confirm overlay is translucent and visible above normal windows.
3. Move and resize the overlay.
4. Switch Spaces and full-screen apps.
5. Confirm overlay joins Spaces and behaves as a full-screen auxiliary panel.
6. Toggle click-through and opacity if exposed in the UI.

Expected result: overlay remains usable and does not steal activation during presentation.

## 7. Clean Feed

1. Start Clean Share.
2. Confirm a window titled `LiveOverlayTranslator - Clean Feed` opens.
3. Confirm SAFE SHARE appears only while ScreenCaptureKit stream is running.
4. Confirm overlay/settings/diagnostics/Clean Feed windows are excluded from the captured feed.
5. Stop Clean Share.
6. Confirm capture resources stop and SAFE SHARE disappears.

Expected result: current implementation opens a clean feed shell but needs real `SCStream` rendering and self-window exclusion before this can pass.

## 8. Zoom Window Sharing

1. Start Clean Share.
2. In Zoom, choose window sharing.
3. Select `LiveOverlayTranslator - Clean Feed`.
4. Confirm meeting participants see the clean feed without translator overlay windows.
5. Share the physical Entire Screen source as a negative test.
6. Confirm the app does not claim it can hide overlays from that capture mode.

Expected result: only Clean Feed window sharing is safe.

## 9. Google Meet Window Sharing

1. Start Clean Share.
2. In Google Meet, choose window sharing.
3. Select `LiveOverlayTranslator - Clean Feed`.
4. Confirm participants see the clean feed without overlay windows.
5. Confirm Entire Screen sharing is documented as unsafe for hiding overlays.

Expected result: only Clean Feed window sharing is safe.

## 10. Teams Window Sharing

1. Start Clean Share.
2. In Teams, choose window sharing.
3. Select `LiveOverlayTranslator - Clean Feed`.
4. Confirm participants see the clean feed without overlay windows.
5. Confirm Entire Screen sharing is documented as unsafe for hiding overlays.

Expected result: only Clean Feed window sharing is safe.

## 11. Emergency Hide Shortcut

1. Show overlay and Clean Feed.
2. Press the configured emergency hide shortcut.
3. Confirm overlay and auxiliary translator windows hide immediately.
4. Confirm backend streaming is not left in an unsafe state.

Expected result: windows hide immediately. Verify shortcut reliability while another app is focused.

## 12. Sleep And Wake

1. Start app in mock mode.
2. Put Mac to sleep.
3. Wake Mac.
4. Confirm overlay remains responsive.
5. Repeat with real microphone transcription running.
6. Confirm uncertain audio is not replayed automatically after reconnect.

Expected result: interrupted utterances are marked interrupted or recoverable; no duplicate transcription request is created.

## 13. Audio Device Disconnect

1. Select an external microphone.
2. Start microphone capture.
3. Disconnect the device during capture.
4. Confirm the app reports a recoverable audio-device error and removes audio taps.
5. Reconnect or select another device.
6. Confirm capture can restart cleanly.

Expected result: no crash, no stale audio tap, no duplicate active capture session.
