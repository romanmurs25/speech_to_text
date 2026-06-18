import type { Source, Speaker } from "../protocol/schemas.js";

export interface PendingUtterance {
  clientUtteranceId: string;
  sequence: number;
  source: Source;
  speaker: Speaker;
  startedAtMs: number;
  endedAtMs?: number;
}

export interface CorrelatedUtterance extends PendingUtterance {
  openAIItemId: string;
  transcript?: string;
  completed: boolean;
}

export class UtteranceCorrelationStore {
  private readonly pending: PendingUtterance[] = [];
  private readonly byItemId = new Map<string, CorrelatedUtterance>();
  private readonly byClientUtteranceId = new Map<string, PendingUtterance>();

  enqueue(utterance: PendingUtterance): void {
    this.pending.push(utterance);
    this.byClientUtteranceId.set(utterance.clientUtteranceId, utterance);
  }

  markEnded(clientUtteranceId: string, endedAtMs: number): PendingUtterance | null {
    const utterance = this.byClientUtteranceId.get(clientUtteranceId);
    if (!utterance) {
      return null;
    }

    utterance.endedAtMs = endedAtMs;
    return utterance;
  }

  markCommitted(openAIItemId: string): CorrelatedUtterance | null {
    const next = this.pending.shift();
    if (!next) {
      return null;
    }

    const correlated: CorrelatedUtterance = {
      ...next,
      openAIItemId,
      completed: false
    };
    this.byItemId.set(openAIItemId, correlated);
    return correlated;
  }

  getByOpenAIItemId(openAIItemId: string): CorrelatedUtterance | undefined {
    return this.byItemId.get(openAIItemId);
  }

  getByClientUtteranceId(clientUtteranceId: string): PendingUtterance | undefined {
    return this.byClientUtteranceId.get(clientUtteranceId);
  }

  complete(openAIItemId: string, transcript: string): CorrelatedUtterance | null {
    const utterance = this.byItemId.get(openAIItemId);
    if (!utterance || utterance.completed) {
      return null;
    }

    utterance.completed = true;
    utterance.transcript = transcript;
    return utterance;
  }
}
