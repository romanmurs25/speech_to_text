# LiveOverlayTranslator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a production-oriented vertical slice of a native macOS bilingual live overlay translator with backend OpenAI API integration boundaries and mock-mode operation.

**Architecture:** The macOS app owns capture, endpoint detection, UI, and Clean Share windows. The Node backend owns protocol validation, OpenAI Realtime transcription sessions, Responses API calls, redaction, rate limits, and idempotency. Both sides share equivalent message contracts and protect UI state using utterance IDs and sequence numbers.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit, XCTest, Node.js 22, TypeScript strict mode, Fastify, ws, OpenAI JavaScript SDK, Zod, pino, Vitest.

---

### Task 1: Documentation And Contracts

**Files:**
- Create: `docs/architecture.md`
- Create: `docs/protocol.md`
- Create: `docs/privacy.md`
- Create: `docs/implementation-plan.md`
- Create: `README.md`
- Create: `.env.example`
- Create: `.gitignore`

- [x] Write architecture documentation covering data flow, component boundaries, WebSocket protocol, privacy decisions, and phases.
- [x] Write protocol documentation for all client and server messages.
- [x] Write privacy documentation for audio, text, key handling, logging, permissions, and Clean Share limitations.
- [x] Add concise implementation plan.

### Task 2: Backend Protocol And Services

**Files:**
- Create: `server/package.json`
- Create: `server/tsconfig.json`
- Create: `server/vitest.config.ts`
- Create: `server/src/**/*.ts`
- Create: `server/tests/**/*.test.ts`

- [x] Write failing Vitest tests for protocol validation, correlation, dialogue context, dedupe, redaction, mock routing, and Responses parsing.
- [x] Implement strict Zod schemas and TypeScript types.
- [x] Implement session manager, Realtime event router, correlation store, dialogue context service, deduplicator, redacting logger, mock clients, and real OpenAI client boundaries.
- [x] Implement Fastify plus `ws` WebSocket endpoint with JSON and binary frame handling.
- [x] Run `npm install`, `npm run typecheck`, `npm test`, and `npm run build`.

### Task 3: macOS App Shell And State

**Files:**
- Create: `macos/LiveOverlayTranslator/Package.swift`
- Create: `macos/LiveOverlayTranslator/Sources/LiveOverlayTranslator/**/*.swift`
- Create: `macos/LiveOverlayTranslator/Tests/LiveOverlayTranslatorTests/**/*.swift`
- Create: `macos/LiveOverlayTranslator/LiveOverlayTranslator.xcodeproj/project.pbxproj`
- Create: `macos/LiveOverlayTranslator/LiveOverlayTranslator.entitlements`

- [x] Write failing Swift tests for Codable messages, endpoint detection, pre-roll, transcript assembly, stale-result protection, dialogue context rules, and mock end-to-end overlay state.
- [x] Implement protocol models and app state.
- [x] Implement SwiftUI overlay views and AppKit `NSPanel` controller.
- [x] Implement mock event source, backend WebSocket shell, microphone capture service, PCM helpers, endpoint detector, Clean Share coordinator shell, diagnostics model, and global shortcut shell.
- [x] Run `swift build`. `swift test` is blocked by the installed Command Line Tools missing usable `XCTest` and Swift Testing module dependencies. `xcodebuild` is blocked because full Xcode is not selected.

### Task 4: Integration Verification

**Files:**
- Modify: `README.md`

- [x] Verify mock backend and mock macOS logic run without `OPENAI_API_KEY`.
- [x] Verify the backend never exposes `OPENAI_API_KEY` to the client.
- [x] Document setup, permissions, run, test, and known limitations.
- [x] Record commands run and results in the final response.
