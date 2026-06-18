import { describe, expect, it } from "vitest";
import { DialogueContextService } from "../src/services/DialogueContextService.js";

describe("dialogue context", () => {
  it("includes only verified real speech turns", () => {
    const dialogue = new DialogueContextService({ maxTurns: 10 });
    dialogue.addSpeechTurn({ speaker: "remote", text: "Did you review it?", sequence: 1 });
    dialogue.addSuggestedReply({
      suggestedReplyEn: "I am reviewing it now.",
      suggestedReplyRu: "I am reviewing it now.",
      sequence: 2
    });
    dialogue.addSpeechTurn({ speaker: "local", text: "I am reviewing it now.", sequence: 3 });

    expect(dialogue.context()).toEqual([
      { speaker: "remote", text: "Did you review it?" },
      { speaker: "local", text: "I am reviewing it now." }
    ]);
  });

  it("keeps the latest bounded context window in sequence order", () => {
    const dialogue = new DialogueContextService({ maxTurns: 3 });
    for (let i = 1; i <= 5; i += 1) {
      dialogue.addSpeechTurn({
        speaker: i % 2 === 0 ? "local" : "remote",
        text: `turn ${i}`,
        sequence: i
      });
    }

    expect(dialogue.context().map((turn) => turn.text)).toEqual(["turn 3", "turn 4", "turn 5"]);
  });
});
