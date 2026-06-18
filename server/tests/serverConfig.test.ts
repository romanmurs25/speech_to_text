import { describe, expect, it } from "vitest";
import { createApp } from "../src/server.js";

describe("server configuration", () => {
  it("fails before listening when real OpenAI mode has no API key", async () => {
    await expect(
      createApp({
        host: "127.0.0.1",
        port: 0,
        mockOpenAI: false,
        openAIApiKey: "",
        openAITextModel: "gpt-5.4-mini",
        openAIRealtimeModel: "gpt-realtime-whisper",
        openAIRealtimeDelay: "low",
        logLevel: "silent"
      })
    ).rejects.toThrow("OPENAI_API_KEY is required when MOCK_OPENAI=false");
  });
});
