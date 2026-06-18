import type { FinalUtteranceEnvelope, OverlayResult } from "../protocol/schemas.js";
import type { OverlayResponseClient } from "../services/OverlayResponseService.js";

export class MockOpenAIResponsesClient implements OverlayResponseClient {
  async createOverlayResult(envelope: FinalUtteranceEnvelope): Promise<OverlayResult> {
    const replyNeeded = envelope.speaker === "remote" && envelope.source_text.trim().endsWith("?");
    return {
      utterance_id: envelope.utterance_id,
      detected_language: "en",
      original_text: envelope.source_text,
      translation_ru: `${envelope.source_text} in Russian`,
      translation_en: envelope.source_text,
      reply_needed: replyNeeded,
      suggested_reply_ru: replyNeeded ? "Yes, I will follow up on that." : "",
      suggested_reply_en: replyNeeded ? "Yes, I will follow up on that." : ""
    };
  }
}
