# LiveOverlayTranslator Privacy Notes

## Where Audio Travels

1. Microphone audio is captured locally by the macOS app after the user grants microphone permission.
2. System audio or display capture is captured locally through ScreenCaptureKit after the user grants screen-recording permission.
3. The macOS app converts audio to PCM S16LE mono 24 kHz.
4. During an active stream, audio chunks travel from the macOS app to the configured backend WebSocket.
5. The backend forwards audio chunks to an OpenAI Realtime transcription session.
6. In-memory audio buffers are cleared after commit, interruption, or failure.

Raw audio is not written to disk by this project and is not logged.

## Where Text Travels

1. Provisional transcript deltas travel from OpenAI Realtime to the backend, then to the macOS overlay.
2. Final completed transcripts are stored in bounded in-memory dialogue context.
3. The backend sends a finalized transcript plus a small verified conversation context window to the OpenAI Responses API to produce translations and optional suggested replies.
4. Suggested replies are not added to dialogue context unless the user marks them as used or local microphone transcription later confirms that the user spoke them.

Transcript text is redacted in production logs by default.

## API Keys

`OPENAI_API_KEY` belongs only on the backend. It is loaded from environment variables. The macOS app does not bundle the key, print the key, or send it over the client protocol.

## OpenAI API Settings

Responses API calls set `store: false`. The backend uses explicit verified context instead of blindly chaining `previous_response_id`, because displayed suggested replies may never have been spoken.

## Clean Share Mode

Clean Share creates a separate ScreenCaptureKit feed window and excludes every window owned by LiveOverlayTranslator where possible. The SAFE SHARE indicator appears only while that clean stream is running.

The user must share the `LiveOverlayTranslator - Clean Feed` window in Zoom, Google Meet, Teams, or another conference app. If the user shares the physical Entire Screen source, LiveOverlayTranslator cannot forcibly hide its overlay from that third-party capture.

## Permissions

macOS prompts for:

- microphone access for microphone transcription;
- screen recording for system audio/display capture and Clean Share;
- accessibility access only if future global shortcut implementations require it beyond Carbon hotkeys.

The UI explains why each permission is requested before opening the relevant system permission flow.

## Logging

Development logs may include event types, IDs, source, speaker, sequence, sizes, and status transitions. Production logs redact:

- raw transcript text;
- raw audio;
- API keys and authorization headers;
- private window titles in diagnostics.

Diagnostic window inclusion and exclusion state is available in-app without logging private production window titles.
