import type { DialogueTurn, Speaker } from "../protocol/schemas.js";

export interface DialogueContextOptions {
  maxTurns?: number;
}

interface StoredSpeechTurn extends DialogueTurn {
  sequence: number;
}

export class DialogueContextService {
  private readonly maxTurns: number;
  private readonly turns: StoredSpeechTurn[] = [];

  constructor(options: DialogueContextOptions = {}) {
    this.maxTurns = options.maxTurns ?? 10;
  }

  addSpeechTurn(turn: { speaker: Speaker; text: string; sequence: number }): void {
    const text = turn.text.trim();
    if (!text) {
      return;
    }

    this.turns.push({ speaker: turn.speaker, text, sequence: turn.sequence });
    this.turns.sort((a, b) => a.sequence - b.sequence);
    if (this.turns.length > this.maxTurns) {
      this.turns.splice(0, this.turns.length - this.maxTurns);
    }
  }

  addSuggestedReply(_reply: {
    suggestedReplyRu: string;
    suggestedReplyEn: string;
    sequence: number;
  }): void {
    // Displayed suggestions are not verified dialogue until spoken or marked used.
  }

  markSuggestedReplyUsed(reply: {
    speaker?: Speaker;
    text: string;
    sequence: number;
  }): void {
    this.addSpeechTurn({
      speaker: reply.speaker ?? "local",
      text: reply.text,
      sequence: reply.sequence
    });
  }

  context(): DialogueTurn[] {
    return this.turns
      .slice(-this.maxTurns)
      .map((turn) => ({ speaker: turn.speaker, text: turn.text }));
  }
}
