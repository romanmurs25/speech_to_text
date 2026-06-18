import { describe, expect, it } from "vitest";
import { UtteranceCorrelationStore } from "../src/services/UtteranceCorrelationStore.js";

describe("utterance correlation", () => {
  it("associates committed OpenAI item IDs with pending client utterances", () => {
    const store = new UtteranceCorrelationStore();
    store.enqueue({
      clientUtteranceId: "client-a",
      sequence: 7,
      source: "microphone",
      speaker: "local",
      startedAtMs: 100
    });
    store.requestCommit("client-a", 7, 200);

    const committed = store.markCommitted("item-a");

    expect(committed?.clientUtteranceId).toBe("client-a");
    expect(store.getByOpenAIItemId("item-a")?.sequence).toBe(7);
  });

  it("reconciles completion events by item ID instead of arrival order", () => {
    const store = new UtteranceCorrelationStore();
    store.enqueue({
      clientUtteranceId: "client-a",
      sequence: 1,
      source: "microphone",
      speaker: "local",
      startedAtMs: 100
    });
    store.requestCommit("client-a", 1, 150);
    store.enqueue({
      clientUtteranceId: "client-b",
      sequence: 2,
      source: "systemAudio",
      speaker: "remote",
      startedAtMs: 200
    });
    store.requestCommit("client-b", 2, 250);

    store.markCommitted("item-a");
    store.markCommitted("item-b");

    expect(store.complete("item-b", "second")?.clientUtteranceId).toBe("client-b");
    expect(store.complete("item-a", "first")?.clientUtteranceId).toBe("client-a");
  });

  it("ignores duplicate completions for the same OpenAI item", () => {
    const store = new UtteranceCorrelationStore();
    store.enqueue({
      clientUtteranceId: "client-a",
      sequence: 1,
      source: "microphone",
      speaker: "local",
      startedAtMs: 100
    });
    store.requestCommit("client-a", 1, 150);
    store.markCommitted("item-a");

    expect(store.complete("item-a", "first")?.transcript).toBe("first");
    expect(store.complete("item-a", "duplicate")).toBeNull();
  });
});
