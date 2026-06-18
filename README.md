# LiveOverlayTranslator

LiveOverlayTranslator is a native macOS live conversation overlay with a Node.js backend. It transcribes completed speech utterances, translates them into Russian and English, optionally suggests concise replies in both languages, and displays the result in a translucent always-on-top overlay.

The app also includes Clean Share mode: the local overlay remains visible to the user, while a separate clean feed window excludes LiveOverlayTranslator windows. In a meeting app, share the `LiveOverlayTranslator - Clean Feed` window, not the physical Entire Screen source.

## Repository Layout

```text
/macos   Swift 6 macOS app, SwiftUI, AppKit, ScreenCaptureKit boundaries
/server  Node.js 22 TypeScript backend, Fastify, ws, OpenAI SDK, Zod
/docs    Architecture, protocol, privacy, and implementation plan
```

## Backend Setup

```bash
cd server
npm install
cp ../.env.example .env
npm run dev
```

Mock mode works without an API key when `MOCK_OPENAI=true`.

For real OpenAI API calls, set:

```bash
OPENAI_API_KEY=sk-...
MOCK_OPENAI=false
```

The default text model is `gpt-5.4-mini` and can be changed with `OPENAI_TEXT_MODEL`.

## Backend Commands

```bash
cd server
npm run typecheck
npm test
npm run build
```

Verified in this workspace:

- `npm install` completed with 0 vulnerabilities.
- `npm run typecheck` passed.
- `npm test` passed: 7 files, 16 tests.
- `npm run build` passed.
- Mock backend `/health` returned `{"ok":true,"mockOpenAI":true}`.
- Mock WebSocket flow returned `session_state`, `transcript_delta`, `transcript_completed`, and `overlay_result` without `OPENAI_API_KEY`.

## macOS Setup

The Swift package lives at `macos/LiveOverlayTranslator`.

```bash
cd macos/LiveOverlayTranslator
swift test
swift build
```

Open `macos/LiveOverlayTranslator/LiveOverlayTranslator.xcodeproj` in Xcode for the native app target. Minimum macOS version is 14.

Verified in this workspace:

- `swift build` passed for the package and executable target.
- `swift test` could not run in the installed Command Line Tools environment: `XCTest` is missing, and enabling Swift Testing finds `Testing.framework` only with a manual framework path but then fails on `_Testing_Foundation`. The test files are present under `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests`.
- `xcodebuild` could not run because the active developer directory is `/Library/Developer/CommandLineTools`; full Xcode is required.

## macOS Permissions

The app explains and requests:

- microphone access for local speech transcription;
- screen recording for system audio/display capture and Clean Share;
- global shortcut access where required by the operating system.

## Development Run Flow

1. Start the backend in mock mode:

   ```bash
   cd server
   MOCK_OPENAI=true npm run dev
   ```

2. Run the macOS app from Xcode or run Swift tests from the package.
3. In mock mode, a simulated transcript completion produces a simulated translation and reply without calling OpenAI.
4. For real microphone transcription, start the backend with `MOCK_OPENAI=false` and a valid `OPENAI_API_KEY`.

## What The Current Vertical Slice Includes

- Backend protocol validation for all client control messages.
- Backend mock mode with end-to-end WebSocket transcript and overlay result messages.
- OpenAI Realtime and Responses API integration boundaries behind interfaces.
- Responses API Structured Output schema and redacted logging.
- Native SwiftUI/AppKit overlay hosted in a translucent floating `NSPanel`.
- Mock macOS event source that produces transcript delta, final transcript, and overlay result updates.
- Microphone capture service scaffold with AVFoundation PCM conversion.
- ScreenCaptureKit-based System Audio and Clean Share coordinator boundaries.
- Global shortcut shell for overlay toggle and emergency hide.

## Remaining Limitations

- Real microphone transcription requires running the app with macOS microphone permission and a backend configured with `MOCK_OPENAI=false`.
- System audio capture and Clean Feed rendering are scaffolded with ScreenCaptureKit permission/diagnostic boundaries, but full stream rendering must be verified in a signed app with screen-recording permission.
- The Xcode project wrapper is present, but `xcodebuild` verification requires full Xcode rather than Command Line Tools.
- Swift unit tests are written but blocked by this machine's Command Line Tools test-framework installation.

## Privacy Defaults

- `OPENAI_API_KEY` exists only on the backend.
- Raw audio is not logged.
- Transcript text is redacted in production logs by default.
- Responses API requests set `store: false`.
- Suggested replies are not treated as real dialogue unless marked used or confirmed by later microphone transcription.

See `docs/privacy.md` for details.

## Clean Share Safety

Clean Share protects the specific flow where the user shares the clean feed window produced by this app. It cannot force unrelated third-party apps to hide overlays when those apps capture the physical Entire Screen source.
