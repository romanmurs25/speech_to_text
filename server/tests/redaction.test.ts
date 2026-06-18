import { describe, expect, it } from "vitest";
import { redactForLog } from "../src/logging/redaction.js";

describe("log redaction", () => {
  it("redacts transcripts, audio payloads, and API credentials by default", () => {
    const redacted = redactForLog({
      transcript: "private words",
      source_text: "more private words",
      audio: "base64audio",
      authorization: "Bearer sk-secret",
      nested: {
        OPENAI_API_KEY: "sk-secret"
      }
    });

    expect(redacted).toEqual({
      transcript: "[REDACTED_TEXT]",
      source_text: "[REDACTED_TEXT]",
      audio: "[REDACTED_AUDIO]",
      authorization: "[REDACTED_SECRET]",
      nested: {
        OPENAI_API_KEY: "[REDACTED_SECRET]"
      }
    });
  });
});
