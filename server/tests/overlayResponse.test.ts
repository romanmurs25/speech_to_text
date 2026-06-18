import { describe, expect, it, vi } from "vitest";
import { OverlayResponseService } from "../src/services/OverlayResponseService.js";
import type { FinalUtteranceEnvelope, OverlayResult } from "../src/protocol/schemas.js";

const envelope: FinalUtteranceEnvelope = {
  session_id: "550e8400-e29b-41d4-a716-446655440000",
  utterance_id: "item_003",
  client_utterance_id: "client-003",
  sequence: 12,
  speaker: "remote",
  source: "systemAudio",
  started_at_ms: 100,
  ended_at_ms: 500,
  source_text: "Could you send me the proposal?",
  source_language_hint: null,
  context: [{ speaker: "local", text: "I am finishing it now." }],
  reply_style: "concise_professional"
};

const result: OverlayResult = {
  utterance_id: "item_003",
  detected_language: "en",
  original_text: "Could you send me the proposal?",
  translation_ru: "Could you send me the proposal? in Russian",
  translation_en: "Could you send me the proposal?",
  reply_needed: true,
  suggested_reply_ru: "Yes, I will send it today.",
  suggested_reply_en: "Yes, I will send it today."
};

describe("overlay response service", () => {
  it("deduplicates finalized utterances by session and OpenAI item ID", async () => {
    const client = { createOverlayResult: vi.fn().mockResolvedValue(result) };
    const service = new OverlayResponseService(client);

    await expect(service.translate(envelope)).resolves.toEqual(result);
    await expect(service.translate(envelope)).resolves.toEqual(result);

    expect(client.createOverlayResult).toHaveBeenCalledTimes(1);
  });

  it("returns an explicit safe error for invalid structured output", async () => {
    const client = { createOverlayResult: vi.fn().mockResolvedValue({ invalid: true }) };
    const service = new OverlayResponseService(client);

    await expect(service.translate(envelope)).rejects.toMatchObject({
      code: "invalid_model_output",
      publicMessage: "The translation response could not be displayed safely."
    });
  });

  it("normalizes model refusal without leaking raw parser errors", async () => {
    const client = {
      createOverlayResult: vi.fn().mockRejectedValue({
        code: "model_refusal",
        publicMessage: "The model refused to transform this utterance."
      })
    };
    const service = new OverlayResponseService(client);

    await expect(service.translate(envelope)).rejects.toMatchObject({
      code: "model_refusal",
      publicMessage: "The model refused to transform this utterance."
    });
  });
});
