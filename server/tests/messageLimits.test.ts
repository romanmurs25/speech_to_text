import { describe, expect, it } from "vitest";
import {
  MAX_AUDIO_FRAME_BYTES,
  MAX_JSON_CONTROL_BYTES,
  isOversizedAudioFrame,
  isOversizedControlMessage
} from "../src/ws/messageLimits.js";

describe("WebSocket message limits", () => {
  it("rejects oversized JSON control messages", () => {
    expect(isOversizedControlMessage(Buffer.alloc(MAX_JSON_CONTROL_BYTES))).toBe(false);
    expect(isOversizedControlMessage(Buffer.alloc(MAX_JSON_CONTROL_BYTES + 1))).toBe(true);
  });

  it("rejects oversized binary audio frames", () => {
    expect(isOversizedAudioFrame(Buffer.alloc(MAX_AUDIO_FRAME_BYTES))).toBe(false);
    expect(isOversizedAudioFrame(Buffer.alloc(MAX_AUDIO_FRAME_BYTES + 1))).toBe(true);
  });
});
