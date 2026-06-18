import OpenAI from "openai";
import { zodTextFormat } from "openai/helpers/zod";
import {
  OverlayResultSchema,
  type FinalUtteranceEnvelope,
  type OverlayResult
} from "../protocol/schemas.js";
import { publicError, type OverlayResponseClient } from "../services/OverlayResponseService.js";

const SYSTEM_INSTRUCTION = `You are a real-time bilingual conversation assistant.

You receive a JSON object containing one finalized speech utterance, its speaker, and a small amount of verified conversation context.

Produce an accurate Russian rendering and an accurate English rendering of the utterance.

Rules:

1. Preserve names, numbers, dates, currencies, product names, negation, uncertainty, and the speaker's intent.
2. Do not add information that was not spoken.
3. translation_ru must always contain a natural Russian rendering.
4. translation_en must always contain a natural English rendering. If the source is already English, lightly normalize it without changing meaning.
5. Generate a suggested reply only when speaker is remote and a response is useful.
6. The suggested reply must be written in the first person as the local user.
7. suggested_reply_ru and suggested_reply_en must express the same meaning.
8. Keep each suggested reply to no more than two concise sentences.
9. Do not invent commitments, prices, deadlines, permissions, or facts.
10. If the utterance is incomplete, unintelligible, or does not require a response, set reply_needed to false and return empty strings for both suggested reply fields.
11. Follow the requested reply style.
12. Return only data matching the supplied Structured Output schema.`;

export interface OpenAIResponsesClientOptions {
  apiKey: string;
  model?: string;
  timeoutMs?: number;
}

export class OpenAIResponsesClient implements OverlayResponseClient {
  private readonly client: OpenAI;
  private readonly model: string;
  private readonly timeoutMs: number;

  constructor(options: OpenAIResponsesClientOptions) {
    this.client = new OpenAI({ apiKey: options.apiKey });
    this.model = options.model ?? process.env.OPENAI_TEXT_MODEL ?? "gpt-5.4-mini";
    this.timeoutMs = options.timeoutMs ?? 20_000;
  }

  async createOverlayResult(envelope: FinalUtteranceEnvelope): Promise<OverlayResult> {
    const response = await retryOnce(async () => {
      const abortController = new AbortController();
      const timer = setTimeout(() => abortController.abort(), this.timeoutMs);
      try {
        return await this.client.responses.parse(
          {
            model: this.model,
            instructions: SYSTEM_INSTRUCTION,
            input: JSON.stringify(envelope),
            store: false,
            reasoning: { effort: "none" },
            max_output_tokens: 500,
            text: {
              format: zodTextFormat(OverlayResultSchema, "overlay_result")
            }
          },
          { signal: abortController.signal }
        );
      } finally {
        clearTimeout(timer);
      }
    });

    const output = response.output_parsed;
    if (!output) {
      throw publicError("invalid_model_output", "The translation response could not be displayed safely.");
    }

    const parsed = OverlayResultSchema.safeParse(output);
    if (!parsed.success) {
      throw publicError("invalid_model_output", "The translation response could not be displayed safely.");
    }

    return parsed.data;
  }
}

async function retryOnce<T>(operation: () => Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (firstError) {
    if (!isTransient(firstError)) {
      throw firstError;
    }

    await new Promise((resolve) => setTimeout(resolve, 150));
    return operation();
  }
}

function isTransient(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }

  const status = "status" in error ? Number((error as { status: unknown }).status) : 0;
  const code = "code" in error ? String((error as { code: unknown }).code) : "";
  return status === 408 || status === 409 || status === 429 || status >= 500 || code === "ETIMEDOUT";
}
