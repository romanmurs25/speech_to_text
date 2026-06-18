import { describe, expect, it } from "vitest";
import {
  ClientControlMessageSchema,
  OverlayResultSchema,
  parseClientControlMessage
} from "../src/protocol/schemas.js";

describe("client protocol validation", () => {
  it("accepts hello and start_stream control messages", () => {
    expect(
      ClientControlMessageSchema.parse({
        type: "hello",
        protocol_version: 1,
        client_version: "0.1.0",
        session_id: "550e8400-e29b-41d4-a716-446655440000"
      }).type
    ).toBe("hello");

    expect(
      ClientControlMessageSchema.parse({
        type: "start_stream",
        source: "microphone",
        sample_rate: 24000,
        channels: 1,
        encoding: "pcm_s16le",
        language_hint: null
      }).type
    ).toBe("start_stream");
  });

  it("accepts utterance_cancel control messages with controlled reasons", () => {
    expect(
      ClientControlMessageSchema.parse({
        type: "utterance_cancel",
        client_utterance_id: "client-1",
        sequence: 12,
        reason: "minimum_speech_duration_not_met"
      }).type
    ).toBe("utterance_cancel");

    expect(() =>
      ClientControlMessageSchema.parse({
        type: "utterance_cancel",
        client_utterance_id: "client-1",
        sequence: 12,
        reason: "not_a_reason"
      })
    ).toThrow();
  });

  it("rejects malformed control messages without leaking parser details", () => {
    const parsed = parseClientControlMessage({
      type: "utterance_start",
      source: "systemAudio",
      speaker: "local",
      sequence: -1,
      started_at_ms: 0
    });

    expect(parsed.ok).toBe(false);
    expect(parsed.ok ? "" : parsed.error.code).toBe("protocol_violation");
    expect(parsed.ok ? "" : parsed.error.message).toBe("Malformed client message.");
  });

  it("parses the structured overlay result schema", () => {
    const result = OverlayResultSchema.parse({
      utterance_id: "item_003",
      detected_language: "en",
      original_text: "Could you send the proposal?",
      translation_ru: "Could you send the proposal? in Russian",
      translation_en: "Could you send the proposal?",
      reply_needed: true,
      suggested_reply_ru: "Yes, I will send it today.",
      suggested_reply_en: "Yes, I will send it today."
    });

    expect(result.utterance_id).toBe("item_003");
    expect(result.reply_needed).toBe(true);
  });
});
