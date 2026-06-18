import { describe, expect, it } from "vitest";
import { RealtimeEventRouter } from "../src/openai/RealtimeEventRouter.js";
import { UtteranceCorrelationStore } from "../src/services/UtteranceCorrelationStore.js";

describe("RealtimeEventRouter", () => {
  it("routes deltas and completions through item correlation", () => {
    const store = new UtteranceCorrelationStore();
    store.enqueue({
      clientUtteranceId: "client-a",
      sequence: 4,
      source: "systemAudio",
      speaker: "remote",
      startedAtMs: 100
    });
    store.markCommitted("item-a");

    const router = new RealtimeEventRouter(store);

    expect(
      router.route({
        type: "conversation.item.input_audio_transcription.delta",
        item_id: "item-a",
        delta: "Could you"
      })
    ).toEqual({
      type: "transcript_delta",
      client_utterance_id: "client-a",
      openai_item_id: "item-a",
      sequence: 4,
      source: "systemAudio",
      speaker: "remote",
      delta: "Could you"
    });

    expect(
      router.route({
        type: "conversation.item.input_audio_transcription.completed",
        item_id: "item-a",
        transcript: "Could you send it?"
      })
    ).toMatchObject({
      type: "transcript_completed",
      client_utterance_id: "client-a",
      transcript: "Could you send it?"
    });
  });

  it("ignores unknown or duplicate completion events", () => {
    const router = new RealtimeEventRouter(new UtteranceCorrelationStore());

    expect(
      router.route({
        type: "conversation.item.input_audio_transcription.completed",
        item_id: "missing",
        transcript: "hello"
      })
    ).toBeNull();
  });
});
