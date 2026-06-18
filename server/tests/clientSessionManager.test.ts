import { describe, expect, it } from "vitest";
import { ClientSessionManager } from "../src/ws/ClientSessionManager.js";
import { MockOpenAIResponsesClient } from "../src/openai/MockOpenAIResponsesClient.js";
import type { RealtimeTranscriptionClient } from "../src/openai/OpenAIRealtimeTranscriptionClient.js";
import type { FinalUtteranceEnvelope, OverlayResult } from "../src/protocol/schemas.js";

describe("ClientSessionManager", () => {
  it("runs the mock utterance flow from completed transcript to overlay result", async () => {
    const messages: unknown[] = [];
    const manager = new ClientSessionManager({
      mockMode: true,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: (message) => messages.push(message)
    });

    manager.handleControl({
      type: "hello",
      protocol_version: 1,
      client_version: "0.1.0",
      session_id: "550e8400-e29b-41d4-a716-446655440000"
    });
    manager.handleControl({
      type: "start_stream",
      source: "microphone",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });
    manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "client-1",
      source: "microphone",
      speaker: "local",
      sequence: 1,
      started_at_ms: 100
    });
    manager.handleAudio(Buffer.from([0, 1, 2, 3]));
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "client-1",
      sequence: 1,
      ended_at_ms: 500
    });

    expect(messages.map((message) => (message as { type: string }).type)).toEqual([
      "session_state",
      "transcript_delta",
      "transcript_completed",
      "overlay_result"
    ]);
    expect(messages.at(-1)).toMatchObject({
      type: "overlay_result",
      client_utterance_id: "client-1",
      sequence: 1,
      result: {
        utterance_id: "mock-item-1",
        original_text: "Could you send me the revised proposal by Friday?",
        translation_ru: "Не могли бы вы прислать мне обновлённое предложение к пятнице?",
        reply_needed: false
      }
    });
  });

  it("does not create overlay results from transcript deltas alone", () => {
    const messages: unknown[] = [];
    const manager = new ClientSessionManager({
      mockMode: true,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: (message) => messages.push(message)
    });

    manager.handleControl({
      type: "hello",
      protocol_version: 1,
      client_version: "0.1.0",
      session_id: "550e8400-e29b-41d4-a716-446655440000"
    });
    manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "client-1",
      source: "microphone",
      speaker: "local",
      sequence: 1,
      started_at_ms: 100
    });

    expect(messages.some((message) => (message as { type: string }).type === "overlay_result")).toBe(false);
  });

  it("surfaces OpenAI Realtime disconnects without replaying committed audio", () => {
    const messages: unknown[] = [];
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: (message) => messages.push(message)
    });

    manager.handleRealtimeDisconnect("microphone");

    expect(messages).toEqual([
      {
        type: "recoverable_error",
        code: "openai_realtime_disconnected",
        message: "Transcription disconnected. The interrupted utterance was not committed or replayed."
      }
    ]);
  });

  it("routes audio and commit to the active microphone Realtime client", async () => {
    const microphoneClient = new RecordingRealtimeClient();
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: () => {},
      realtimeClientFactory: () => microphoneClient
    });

    await manager.handleControl({
      type: "start_stream",
      source: "microphone",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });
    await manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "client-mic",
      source: "microphone",
      speaker: "local",
      sequence: 1,
      started_at_ms: 100
    });

    manager.handleAudio(Buffer.from([1, 2, 3, 4]));
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "client-mic",
      sequence: 1,
      ended_at_ms: 200
    });

    expect(microphoneClient.appendedBytes).toBe(4);
    expect(microphoneClient.commits).toBe(1);
  });

  it("cancels a short utterance with Realtime clear and accepts the next utterance", async () => {
    const messages: unknown[] = [];
    const microphoneClient = new RecordingRealtimeClient();
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: (message) => messages.push(message),
      realtimeClientFactory: () => microphoneClient
    });

    await manager.handleControl({
      type: "start_stream",
      source: "microphone",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });
    await manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "too-short",
      source: "microphone",
      speaker: "local",
      sequence: 1,
      started_at_ms: 100
    });
    manager.handleAudio(Buffer.from([1, 2, 3, 4]));
    await manager.handleControl({
      type: "utterance_cancel",
      client_utterance_id: "too-short",
      sequence: 1,
      reason: "minimum_speech_duration_not_met"
    });
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "too-short",
      sequence: 1,
      ended_at_ms: 150
    });
    await manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "normal",
      source: "microphone",
      speaker: "local",
      sequence: 2,
      started_at_ms: 200
    });
    manager.handleAudio(Buffer.from([5, 6]));
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "normal",
      sequence: 2,
      ended_at_ms: 400
    });

    expect(microphoneClient.appendedBytes).toBe(6);
    expect(microphoneClient.clears).toBe(1);
    expect(microphoneClient.commits).toBe(1);
    expect(messages).toContainEqual({
      type: "recoverable_error",
      code: "utterance_not_committable",
      message: "The utterance is not active and cannot be committed.",
      client_utterance_id: "too-short"
    });
  });

  it("deduplicates duplicate starts and commits before they reach Realtime", async () => {
    const microphoneClient = new RecordingRealtimeClient();
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: () => {},
      realtimeClientFactory: () => microphoneClient
    });

    await manager.handleControl({
      type: "start_stream",
      source: "microphone",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });
    const start = {
      type: "utterance_start" as const,
      client_utterance_id: "client-dup",
      source: "microphone" as const,
      speaker: "local" as const,
      sequence: 1,
      started_at_ms: 100
    };
    await manager.handleControl(start);
    await manager.handleControl(start);
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "client-dup",
      sequence: 1,
      ended_at_ms: 200
    });
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "client-dup",
      sequence: 1,
      ended_at_ms: 200
    });

    expect(microphoneClient.commits).toBe(1);
  });

  it("fails closed on overlapping utterances so following audio is not routed ambiguously", async () => {
    const messages: unknown[] = [];
    const microphoneClient = new RecordingRealtimeClient();
    let terminated = false;
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: (message) => messages.push(message),
      realtimeClientFactory: () => microphoneClient,
      terminate: () => {
        terminated = true;
      }
    });

    await manager.handleControl({
      type: "start_stream",
      source: "microphone",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });
    await manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "client-a",
      source: "microphone",
      speaker: "local",
      sequence: 1,
      started_at_ms: 100
    });
    await manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "client-b",
      source: "microphone",
      speaker: "local",
      sequence: 2,
      started_at_ms: 120
    });

    manager.handleAudio(Buffer.from([1, 2, 3, 4]));
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "client-a",
      sequence: 1,
      ended_at_ms: 200
    });
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "client-b",
      sequence: 2,
      ended_at_ms: 220
    });

    expect(messages).toEqual([
      {
        type: "fatal_error",
        code: "ambiguous_audio_routing",
        message: "The audio stream entered an ambiguous utterance state."
      }
    ]);
    expect(terminated).toBe(true);
    expect(microphoneClient.appendedBytes).toBe(0);
    expect(microphoneClient.commits).toBe(0);
    expect(microphoneClient.clears).toBe(1);
  });

  it("clears active and pending state on stop_stream", async () => {
    const microphoneClient = new RecordingRealtimeClient();
    const messages: unknown[] = [];
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: (message) => messages.push(message),
      realtimeClientFactory: () => microphoneClient
    });

    await manager.handleControl({
      type: "start_stream",
      source: "microphone",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });
    await manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "client-stop",
      source: "microphone",
      speaker: "local",
      sequence: 1,
      started_at_ms: 100
    });
    await manager.handleControl({
      type: "stop_stream",
      source: "microphone"
    });
    await manager.handleControl({
      type: "utterance_commit",
      client_utterance_id: "client-stop",
      sequence: 1,
      ended_at_ms: 200
    });

    expect(microphoneClient.clears).toBe(1);
    expect(microphoneClient.closes).toBe(1);
    expect(microphoneClient.commits).toBe(0);
  });

  it("rejects system audio start safely in P0 mode", async () => {
    const messages: unknown[] = [];
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: (message) => messages.push(message)
    });

    await manager.handleControl({
      type: "start_stream",
      source: "systemAudio",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });

    expect(messages).toEqual([
      {
        type: "recoverable_error",
        code: "source_unavailable",
        message: "System audio capture is not available in the P0 microphone build."
      }
    ]);
  });

  it("preserves completed speech in future context when translation fails", async () => {
    const messages: unknown[] = [];
    const overlayClient = new RecordingOverlayResponseClient([
      Promise.reject(new Error("Responses outage")),
      Promise.resolve(makeOverlayResult("item-2", "Second real turn"))
    ]);
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: overlayClient,
      send: (message) => messages.push(message)
    });

    manager.handleControl({
      type: "hello",
      protocol_version: 1,
      client_version: "0.1.0",
      session_id: "550e8400-e29b-41d4-a716-446655440000"
    });
    await completeRealtimeUtterance(manager, "client-1", 1, "item-1", "First real turn");
    await completeRealtimeUtterance(manager, "client-2", 2, "item-2", "Second real turn");

    expect(overlayClient.envelopes).toHaveLength(2);
    expect(overlayClient.envelopes[0].context).toEqual([]);
    expect(overlayClient.envelopes[1].context).toEqual([
      { speaker: "local", text: "First real turn" }
    ]);
    expect(overlayClient.envelopes[1].context).not.toContainEqual({
      speaker: "local",
      text: "Second real turn"
    });
    expect(messages).toContainEqual({
      type: "recoverable_error",
      code: "translation_failed",
      message: "Translation is temporarily unavailable.",
      client_utterance_id: "client-1"
    });
    expect(messages).toContainEqual({
      type: "overlay_result",
      client_utterance_id: "client-2",
      sequence: 2,
      result: makeOverlayResult("item-2", "Second real turn")
    });
  });
});

async function completeRealtimeUtterance(
  manager: ClientSessionManager,
  clientUtteranceId: string,
  sequence: number,
  itemId: string,
  transcript: string
): Promise<void> {
  await manager.handleControl({
    type: "utterance_start",
    client_utterance_id: clientUtteranceId,
    source: "microphone",
    speaker: "local",
    sequence,
    started_at_ms: sequence * 100
  });
  await manager.handleControl({
    type: "utterance_commit",
    client_utterance_id: clientUtteranceId,
    sequence,
    ended_at_ms: sequence * 100 + 50
  });
  await manager.handleRealtimeEvent({
    type: "input_audio_buffer.committed",
    item_id: itemId
  });
  await manager.handleRealtimeEvent({
    type: "conversation.item.input_audio_transcription.completed",
    item_id: itemId,
    transcript
  });
}

function makeOverlayResult(utteranceId: string, text: string): OverlayResult {
  return {
    utterance_id: utteranceId,
    detected_language: "en",
    original_text: text,
    translation_ru: `${text} RU`,
    translation_en: text,
    reply_needed: true,
    suggested_reply_ru: "Да.",
    suggested_reply_en: "Yes."
  };
}

class RecordingOverlayResponseClient {
  readonly envelopes: FinalUtteranceEnvelope[] = [];

  constructor(private readonly responses: Array<Promise<OverlayResult>>) {}

  createOverlayResult(envelope: FinalUtteranceEnvelope): Promise<OverlayResult> {
    this.envelopes.push(envelope);
    return this.responses.shift() ?? Promise.resolve(makeOverlayResult(envelope.utterance_id, envelope.source_text));
  }
}

class RecordingRealtimeClient implements RealtimeTranscriptionClient {
  appendedBytes = 0;
  commits = 0;
  closes = 0;
  clears = 0;

  appendAudio(pcm: Buffer): void {
    this.appendedBytes += pcm.length;
  }

  commit(): void {
    this.commits += 1;
  }

  clear(): void {
    this.clears += 1;
  }

  close(): void {
    this.closes += 1;
  }
}
