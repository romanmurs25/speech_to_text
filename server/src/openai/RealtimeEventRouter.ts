import type {
  ServerMessage,
  TranscriptCompletedMessage,
  TranscriptDeltaMessage
} from "../protocol/schemas.js";
import { UtteranceCorrelationStore } from "../services/UtteranceCorrelationStore.js";

export type OpenAIRealtimeEvent =
  | {
      type: "input_audio_buffer.committed";
      item_id?: string;
      item?: { id?: string };
    }
  | {
      type: "conversation.item.input_audio_transcription.delta";
      item_id?: string;
      item_id_old?: string;
      delta?: string;
    }
  | {
      type: "conversation.item.input_audio_transcription.completed";
      item_id?: string;
      transcript?: string;
    }
  | {
      type: "error" | "rate_limits.updated" | "session.created" | "session.updated";
      [key: string]: unknown;
    };

export class RealtimeEventRouter {
  constructor(private readonly correlationStore: UtteranceCorrelationStore) {}

  route(event: OpenAIRealtimeEvent): ServerMessage | null {
    if (event.type === "input_audio_buffer.committed") {
      const itemId = event.item_id ?? event.item?.id;
      if (itemId) {
        this.correlationStore.markCommitted(itemId);
      }
      return null;
    }

    if (event.type === "conversation.item.input_audio_transcription.delta") {
      const itemId = event.item_id ?? event.item_id_old;
      if (!itemId) {
        return null;
      }

      const utterance = this.correlationStore.getByOpenAIItemId(itemId);
      if (!utterance) {
        return null;
      }

      return {
        type: "transcript_delta",
        client_utterance_id: utterance.clientUtteranceId,
        openai_item_id: itemId,
        sequence: utterance.sequence,
        source: utterance.source,
        speaker: utterance.speaker,
        delta: event.delta ?? ""
      } satisfies TranscriptDeltaMessage;
    }

    if (event.type === "conversation.item.input_audio_transcription.completed") {
      if (!event.item_id || !event.transcript?.trim()) {
        return null;
      }

      const utterance = this.correlationStore.complete(event.item_id, event.transcript);
      if (!utterance) {
        return null;
      }

      return {
        type: "transcript_completed",
        client_utterance_id: utterance.clientUtteranceId,
        openai_item_id: event.item_id,
        sequence: utterance.sequence,
        source: utterance.source,
        speaker: utterance.speaker,
        transcript: event.transcript
      } satisfies TranscriptCompletedMessage;
    }

    return null;
  }
}
