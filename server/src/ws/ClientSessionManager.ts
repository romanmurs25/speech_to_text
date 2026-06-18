import type { RawData } from "ws";
import {
  FinalUtteranceEnvelopeSchema,
  type ClientControlMessage,
  type FinalUtteranceEnvelope,
  type ServerMessage
} from "../protocol/schemas.js";
import { RealtimeEventRouter } from "../openai/RealtimeEventRouter.js";
import type { RealtimeTranscriptionClient } from "../openai/OpenAIRealtimeTranscriptionClient.js";
import type { OverlayResponseClient } from "../services/OverlayResponseService.js";
import {
  OverlayResponseService,
  isPublicServiceError
} from "../services/OverlayResponseService.js";
import { DialogueContextService } from "../services/DialogueContextService.js";
import { UtteranceCorrelationStore } from "../services/UtteranceCorrelationStore.js";
import { rawDataToBuffer } from "./rawData.js";

export interface ClientSessionManagerOptions {
  mockMode: boolean;
  overlayResponseClient: OverlayResponseClient;
  send: (message: ServerMessage) => void;
  realtimeClientFactory?: (source: ClientControlMessage & { type: "start_stream" }) => RealtimeTranscriptionClient;
}

export class ClientSessionManager {
  private sessionId: string | null = null;
  private readonly overlayResponses: OverlayResponseService;
  private readonly dialogue = new DialogueContextService({ maxTurns: 10 });
  private readonly correlation = new UtteranceCorrelationStore();
  private readonly router = new RealtimeEventRouter(this.correlation);
  private readonly realtimeClients = new Map<string, RealtimeTranscriptionClient>();
  private activeClientUtteranceId: string | null = null;

  constructor(private readonly options: ClientSessionManagerOptions) {
    this.overlayResponses = new OverlayResponseService(options.overlayResponseClient);
  }

  async handleControl(message: ClientControlMessage): Promise<void> {
    switch (message.type) {
      case "hello":
        this.sessionId = message.session_id;
        this.options.send({
          type: "session_state",
          status: "ready",
          session_id: message.session_id
        });
        return;

      case "start_stream":
        if (!this.options.mockMode && this.options.realtimeClientFactory) {
          this.realtimeClients.set(message.source, this.options.realtimeClientFactory(message));
        }
        return;

      case "utterance_start":
        this.activeClientUtteranceId = message.client_utterance_id;
        this.correlation.enqueue({
          clientUtteranceId: message.client_utterance_id,
          sequence: message.sequence,
          source: message.source,
          speaker: message.speaker,
          startedAtMs: message.started_at_ms
        });
        return;

      case "utterance_commit":
        this.correlation.markEnded(message.client_utterance_id, message.ended_at_ms);
        if (this.options.mockMode) {
          await this.emitMockCompletion(message.client_utterance_id, message.sequence, message.ended_at_ms);
        } else {
          for (const client of this.realtimeClients.values()) {
            client.commit();
          }
        }
        this.activeClientUtteranceId = null;
        return;

      case "stop_stream":
        this.realtimeClients.get(message.source)?.close();
        this.realtimeClients.delete(message.source);
        return;
    }
  }

  handleAudio(data: RawData | Buffer): void {
    if (this.options.mockMode || !this.activeClientUtteranceId) {
      return;
    }

    const buffer = rawDataToBuffer(data);
    for (const client of this.realtimeClients.values()) {
      client.appendAudio(buffer);
    }
  }

  async handleRealtimeEvent(event: Parameters<RealtimeEventRouter["route"]>[0]): Promise<void> {
    const routed = this.router.route(event);
    if (!routed) {
      return;
    }

    this.options.send(routed);
    if (routed.type === "transcript_completed") {
      await this.createOverlayResult(routed.openai_item_id, routed.transcript);
    }
  }

  close(): void {
    for (const client of this.realtimeClients.values()) {
      client.close();
    }
    this.realtimeClients.clear();
  }

  private async emitMockCompletion(
    clientUtteranceId: string,
    sequence: number,
    endedAtMs: number
  ): Promise<void> {
    const itemId = `mock-item-${sequence}`;
    const transcript = "Could you send me the revised proposal by Friday?";
    this.router.route({ type: "input_audio_buffer.committed", item_id: itemId });

    const delta = this.router.route({
      type: "conversation.item.input_audio_transcription.delta",
      item_id: itemId,
      delta: "Could you send"
    });
    if (delta) {
      this.options.send(delta);
    }

    const completed = this.router.route({
      type: "conversation.item.input_audio_transcription.completed",
      item_id: itemId,
      transcript
    });
    if (completed) {
      this.options.send(completed);
      await this.createOverlayResult(itemId, transcript, clientUtteranceId, sequence, endedAtMs);
    }
  }

  private async createOverlayResult(
    openAIItemId: string,
    transcript: string,
    fallbackClientUtteranceId?: string,
    fallbackSequence?: number,
    fallbackEndedAtMs?: number
  ): Promise<void> {
    const correlated = this.correlation.getByOpenAIItemId(openAIItemId);
    if (!correlated || !this.sessionId) {
      return;
    }

    const envelope = FinalUtteranceEnvelopeSchema.parse({
      session_id: this.sessionId,
      utterance_id: openAIItemId,
      client_utterance_id: correlated.clientUtteranceId ?? fallbackClientUtteranceId,
      sequence: correlated.sequence ?? fallbackSequence,
      speaker: correlated.speaker,
      source: correlated.source,
      started_at_ms: correlated.startedAtMs,
      ended_at_ms: correlated.endedAtMs ?? fallbackEndedAtMs ?? Date.now(),
      source_text: transcript,
      source_language_hint: null,
      context: this.dialogue.context(),
      reply_style: "concise_professional"
    } satisfies FinalUtteranceEnvelope);

    try {
      const result = await this.overlayResponses.translate(envelope);
      this.dialogue.addSpeechTurn({
        speaker: envelope.speaker,
        text: envelope.source_text,
        sequence: envelope.sequence
      });
      if (result.reply_needed) {
        this.dialogue.addSuggestedReply({
          suggestedReplyRu: result.suggested_reply_ru,
          suggestedReplyEn: result.suggested_reply_en,
          sequence: envelope.sequence
        });
      }
      this.options.send({
        type: "overlay_result",
        client_utterance_id: envelope.client_utterance_id,
        sequence: envelope.sequence,
        result
      });
    } catch (error) {
      this.options.send({
        type: "recoverable_error",
        code: isPublicServiceError(error) ? error.code : "translation_failed",
        message: isPublicServiceError(error)
          ? error.publicMessage
          : "Translation is temporarily unavailable.",
        client_utterance_id: envelope.client_utterance_id
      });
    }
  }
}
