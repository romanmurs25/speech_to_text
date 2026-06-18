import type { Source, Speaker, UtteranceCancelReason } from "../protocol/schemas.js";

export type UtteranceLifecycle =
  | "active"
  | "commitRequested"
  | "correlated"
  | "completed"
  | "cancelled"
  | "abandoned";

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

interface UtteranceRecord extends PendingUtterance {
  lifecycle: UtteranceLifecycle;
  openAIItemId?: string;
  transcript?: string;
  cancelReason?: UtteranceCancelReason;
}

export type EnqueueResult = "enqueued" | "duplicate" | "conflict";
export type CommitRequestResult =
  | { ok: true; utterance: PendingUtterance; duplicate: boolean }
  | { ok: false; code: "not_found" | "cancelled" | "abandoned" | "already_committed" | "conflict" };
export type CancelResult =
  | { ok: true; utterance: PendingUtterance; duplicate: boolean }
  | { ok: false; code: "not_found" | "already_committed" | "conflict" };
export interface ClearUnfinishedResult {
  cancelled: PendingUtterance[];
  abandoned: PendingUtterance[];
}

export class UtteranceCorrelationStore {
  private readonly records = new Map<string, UtteranceRecord>();
  private readonly byItemId = new Map<string, UtteranceRecord>();
  private readonly commitQueue: string[] = [];
  private readonly finishedOrder: string[] = [];
  private readonly maxFinishedRecords: number;

  constructor(options: { maxFinishedRecords?: number } = {}) {
    this.maxFinishedRecords = options.maxFinishedRecords ?? 512;
  }

  enqueue(utterance: PendingUtterance): EnqueueResult {
    const existing = this.records.get(utterance.clientUtteranceId);
    if (existing) {
      return sameUtteranceMetadata(existing, utterance) ? "duplicate" : "conflict";
    }

    this.records.set(utterance.clientUtteranceId, {
      ...utterance,
      lifecycle: "active"
    });
    return "enqueued";
  }

  requestCommit(
    clientUtteranceId: string,
    expectedSequence: number,
    endedAtMs: number
  ): CommitRequestResult {
    const record = this.records.get(clientUtteranceId);
    if (!record) {
      return { ok: false, code: "not_found" };
    }

    if (record.sequence !== expectedSequence) {
      return { ok: false, code: "conflict" };
    }

    if (record.lifecycle === "cancelled") {
      return { ok: false, code: "cancelled" };
    }

    if (record.lifecycle === "abandoned") {
      return { ok: false, code: "abandoned" };
    }

    if (record.lifecycle === "commitRequested") {
      if (record.endedAtMs !== endedAtMs) {
        return { ok: false, code: "conflict" };
      }
      return { ok: true, utterance: asPending(record), duplicate: true };
    }

    if (record.lifecycle === "correlated" || record.lifecycle === "completed") {
      return { ok: false, code: "already_committed" };
    }

    if (record.lifecycle !== "active") {
      return { ok: false, code: "conflict" };
    }

    record.lifecycle = "commitRequested";
    record.endedAtMs = endedAtMs;
    this.commitQueue.push(clientUtteranceId);
    return { ok: true, utterance: asPending(record), duplicate: false };
  }

  cancel(
    clientUtteranceId: string,
    reason: UtteranceCancelReason,
    expectedSequence?: number
  ): CancelResult {
    const record = this.records.get(clientUtteranceId);
    if (!record) {
      return { ok: false, code: "not_found" };
    }

    if (expectedSequence !== undefined && record.sequence !== expectedSequence) {
      return { ok: false, code: "conflict" };
    }

    if (record.lifecycle === "cancelled") {
      return { ok: true, utterance: asPending(record), duplicate: true };
    }

    if (
      record.lifecycle === "commitRequested" ||
      record.lifecycle === "correlated" ||
      record.lifecycle === "completed" ||
      record.lifecycle === "abandoned"
    ) {
      return { ok: false, code: "already_committed" };
    }

    record.lifecycle = "cancelled";
    record.cancelReason = reason;
    this.removeFromCommitQueue(clientUtteranceId);
    this.rememberFinished(clientUtteranceId);
    return { ok: true, utterance: asPending(record), duplicate: false };
  }

  markCommitted(openAIItemId: string): CorrelatedUtterance | null {
    while (this.commitQueue.length > 0) {
      const clientUtteranceId = this.commitQueue.shift();
      if (!clientUtteranceId) {
        continue;
      }

      const record = this.records.get(clientUtteranceId);
      if (!record || record.lifecycle !== "commitRequested") {
        continue;
      }

      record.lifecycle = "correlated";
      record.openAIItemId = openAIItemId;
      this.byItemId.set(openAIItemId, record);
      return asCorrelated(record);
    }

    return null;
  }

  getByOpenAIItemId(openAIItemId: string): CorrelatedUtterance | undefined {
    const record = this.byItemId.get(openAIItemId);
    if (!record || record.lifecycle === "cancelled" || record.lifecycle === "abandoned") {
      return undefined;
    }
    return asCorrelated(record);
  }

  getByClientUtteranceId(clientUtteranceId: string): PendingUtterance | undefined {
    const record = this.records.get(clientUtteranceId);
    return record ? asPending(record) : undefined;
  }

  complete(openAIItemId: string, transcript: string): CorrelatedUtterance | null {
    const record = this.byItemId.get(openAIItemId);
    if (!record || record.lifecycle !== "correlated") {
      return null;
    }

    record.lifecycle = "completed";
    record.transcript = transcript;
    this.rememberFinished(record.clientUtteranceId);
    return asCorrelated(record);
  }

  clearUncommittedForSource(source: Source, reason: UtteranceCancelReason): PendingUtterance[] {
    return this.clearUnfinishedForSource(source, reason).cancelled;
  }

  clearUnfinishedForSource(source: Source, reason: UtteranceCancelReason): ClearUnfinishedResult {
    const cancelled: PendingUtterance[] = [];
    const abandoned: PendingUtterance[] = [];
    for (const record of this.records.values()) {
      if (record.source !== source) {
        continue;
      }

      if (record.lifecycle === "active") {
        record.lifecycle = "cancelled";
        record.cancelReason = reason;
        this.removeFromCommitQueue(record.clientUtteranceId);
        this.rememberFinished(record.clientUtteranceId);
        cancelled.push(asPending(record));
        continue;
      }

      if (record.lifecycle === "commitRequested" || record.lifecycle === "correlated") {
        record.lifecycle = "abandoned";
        this.removeFromCommitQueue(record.clientUtteranceId);
        if (record.openAIItemId) {
          this.byItemId.delete(record.openAIItemId);
        }
        this.rememberFinished(record.clientUtteranceId);
        abandoned.push(asPending(record));
      }
    }
    return { cancelled, abandoned };
  }

  private removeFromCommitQueue(clientUtteranceId: string): void {
    for (let index = this.commitQueue.length - 1; index >= 0; index -= 1) {
      if (this.commitQueue[index] === clientUtteranceId) {
        this.commitQueue.splice(index, 1);
      }
    }
  }

  private rememberFinished(clientUtteranceId: string): void {
    this.finishedOrder.push(clientUtteranceId);
    while (this.finishedOrder.length > this.maxFinishedRecords) {
      const expired = this.finishedOrder.shift();
      if (!expired) {
        continue;
      }
      const record = this.records.get(expired);
      if (record?.openAIItemId) {
        this.byItemId.delete(record.openAIItemId);
      }
      this.records.delete(expired);
    }
  }
}

function sameUtteranceMetadata(a: PendingUtterance, b: PendingUtterance): boolean {
  return (
    a.clientUtteranceId === b.clientUtteranceId &&
    a.sequence === b.sequence &&
    a.source === b.source &&
    a.speaker === b.speaker &&
    a.startedAtMs === b.startedAtMs
  );
}

function asPending(record: UtteranceRecord): PendingUtterance {
  return {
    clientUtteranceId: record.clientUtteranceId,
    sequence: record.sequence,
    source: record.source,
    speaker: record.speaker,
    startedAtMs: record.startedAtMs,
    endedAtMs: record.endedAtMs
  };
}

function asCorrelated(record: UtteranceRecord): CorrelatedUtterance {
  return {
    ...asPending(record),
    openAIItemId: record.openAIItemId ?? "",
    transcript: record.transcript,
    completed: record.lifecycle === "completed"
  };
}
