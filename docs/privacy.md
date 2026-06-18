# LiveOverlayTranslator Privacy Notes

## Where Audio Travels

1. Microphone audio is captured locally by the macOS app after the user grants microphone permission.
2. The macOS app converts microphone audio to PCM S16LE mono 24 kHz.
3. During an active stream, small audio frames travel from the macOS app to the configured backend WebSocket.
4. The backend forwards audio frames to an OpenAI Realtime transcription session.
5. In-memory audio buffers are cleared after commit, interruption, or failure.

Raw audio is not written to disk by this project and is not logged. System audio capture is unavailable in the P0 microphone build.

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

Clean Share is not implemented in the P0 microphone build. The app does not create an `SCContentFilter`, `SCStream`, output handler, frame renderer, or clean capture stream.

Do not rely on LiveOverlayTranslator to hide the overlay from screen sharing. If the user shares the physical Entire Screen source in Zoom, Google Meet, Teams, or another conference app, the overlay can be exposed.

## Permissions

macOS prompts for:

- microphone access for microphone transcription;
- screen recording only in future builds that implement system audio or Clean Share;
- accessibility access only if future global shortcut implementations require it beyond Carbon hotkeys.

The UI explains why each permission is requested before opening the relevant system permission flow.

## Logging

Development logs may include event types, IDs, source, speaker, sequence, sizes, and status transitions. Production logs redact:

- raw transcript text;
- raw audio;
- API keys and authorization headers;
- private window titles in diagnostics.

Diagnostic window inclusion and exclusion state is available in-app without logging private production window titles.
