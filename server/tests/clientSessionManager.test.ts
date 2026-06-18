import { describe, expect, it } from "vitest";
import { ClientSessionManager } from "../src/ws/ClientSessionManager.js";
import { MockOpenAIResponsesClient } from "../src/openai/MockOpenAIResponsesClient.js";
import type { RealtimeTranscriptionClient } from "../src/openai/OpenAIRealtimeTranscriptionClient.js";

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
      source: "systemAudio",
      sample_rate: 24000,
      channels: 1,
      encoding: "pcm_s16le",
      language_hint: null
    });
    manager.handleControl({
      type: "utterance_start",
      client_utterance_id: "client-1",
      source: "systemAudio",
      speaker: "remote",
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
        reply_needed: true
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
      source: "systemAudio",
      speaker: "remote",
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
        message: "Transcription disconnected. The interrupted utterance was not replayed automatically."
      }
    ]);
  });

  it("routes audio and commit only to the utterance source Realtime client", async () => {
    const microphoneClient = new RecordingRealtimeClient();
    const systemAudioClient = new RecordingRealtimeClient();
    const manager = new ClientSessionManager({
      mockMode: false,
      overlayResponseClient: new MockOpenAIResponsesClient(),
      send: () => {},
      realtimeClientFactory: (message) =>
        message.source === "microphone" ? microphoneClient : systemAudioClient
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
      type: "start_stream",
      source: "systemAudio",
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
    expect(systemAudioClient.appendedBytes).toBe(0);
    expect(systemAudioClient.commits).toBe(0);
  });
});

class RecordingRealtimeClient implements RealtimeTranscriptionClient {
  appendedBytes = 0;
  commits = 0;
  closes = 0;

  appendAudio(pcm: Buffer): void {
    this.appendedBytes += pcm.length;
  }

  commit(): void {
    this.commits += 1;
  }

  close(): void {
    this.closes += 1;
  }
}
