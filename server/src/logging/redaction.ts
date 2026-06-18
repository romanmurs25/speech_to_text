const TEXT_KEYS = new Set([
  "transcript",
  "source_text",
  "original_text",
  "translation_ru",
  "translation_en",
  "suggested_reply_ru",
  "suggested_reply_en",
  "text",
  "delta"
]);

const AUDIO_KEYS = new Set(["audio", "audio_base64", "pcm", "payload"]);
const SECRET_KEYS = new Set([
  "authorization",
  "Authorization",
  "api_key",
  "OPENAI_API_KEY",
  "openai_api_key"
]);

export function redactForLog<T>(value: T): T {
  return redactValue(value) as T;
}

function redactValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((entry) => redactValue(entry));
  }

  if (!value || typeof value !== "object") {
    return value;
  }

  const output: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value)) {
    if (SECRET_KEYS.has(key)) {
      output[key] = "[REDACTED_SECRET]";
    } else if (AUDIO_KEYS.has(key)) {
      output[key] = "[REDACTED_AUDIO]";
    } else if (TEXT_KEYS.has(key)) {
      output[key] = "[REDACTED_TEXT]";
    } else {
      output[key] = redactValue(nested);
    }
  }

  return output;
}
