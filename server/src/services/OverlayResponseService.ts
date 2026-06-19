import {
  OverlayResultSchema,
  type FinalUtteranceEnvelope,
  type OverlayResult
} from "../protocol/schemas.js";
import { RequestDeduplicator } from "./RequestDeduplicator.js";

export interface OverlayResponseOptions {
  signal?: AbortSignal;
}

export interface OverlayResponseClient {
  createOverlayResult(envelope: FinalUtteranceEnvelope, options?: OverlayResponseOptions): Promise<unknown>;
}

export interface PublicServiceError {
  code: string;
  publicMessage: string;
}

export class OverlayResponseService {
  private readonly deduplicator = new RequestDeduplicator<OverlayResult>();

  constructor(private readonly client: OverlayResponseClient) {}

  async translate(envelope: FinalUtteranceEnvelope, options?: OverlayResponseOptions): Promise<OverlayResult> {
    const key = `${envelope.session_id}:${envelope.utterance_id}`;
    return this.deduplicator.run(key, async () => {
      try {
        throwIfAborted(options?.signal);
        const raw = await this.client.createOverlayResult(envelope, options);
        throwIfAborted(options?.signal);
        const parsed = OverlayResultSchema.safeParse(raw);
        if (!parsed.success) {
          throw publicError(
            "invalid_model_output",
            "The translation response could not be displayed safely."
          );
        }

        return parsed.data;
      } catch (error) {
        if (isAbortError(error)) {
          throw publicError("request_aborted", "Translation request was cancelled.");
        }
        if (isPublicServiceError(error)) {
          throw error;
        }

        throw publicError("translation_failed", "Translation is temporarily unavailable.");
      }
    });
  }
}

export function publicError(code: string, publicMessage: string): PublicServiceError {
  return { code, publicMessage };
}

export function isPublicServiceError(error: unknown): error is PublicServiceError {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    "publicMessage" in error &&
    typeof (error as { code: unknown }).code === "string" &&
    typeof (error as { publicMessage: unknown }).publicMessage === "string"
  );
}

function throwIfAborted(signal: AbortSignal | undefined): void {
  if (!signal?.aborted) {
    return;
  }
  const error = new Error("aborted");
  error.name = "AbortError";
  throw error;
}

function isAbortError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error.name === "AbortError" || error.message.toLowerCase() === "aborted")
  );
}
