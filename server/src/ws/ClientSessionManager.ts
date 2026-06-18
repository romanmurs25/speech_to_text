import type { RawData } from "ws";
import {
  FinalUtteranceEnvelopeSchema,
  type ClientControlMessage,
  type FinalUtteranceEnvelope,
  type Source,
  type ServerMessage
} from "../protocol/schemas.js";
import { RealtimeEventRouter } from "../openai/RealtimeEventRouter.js";
import type { RealtimeTranscriptionClient } from "../openai/OpenAIRealtimeTranscriptionClient.js";
import type { RealtimeTerminalFailure } from "../openai/OpenAIRealtimeTranscriptionClient.js";
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
  send: (message: ServerMessage) => boolean | void;
  realtimeClientFactory?: (source: ClientControlMessage & { type: "start_stream" }) => RealtimeTranscriptionClient;
  terminate?: () => void;
}

export class ClientSessionManager {
  private sessionId: string | null = null;
  private readonly overlayResponses: OverlayResponseService;
  private readonly dialogue = new DialogueContextService({ maxTurns: 10 });
  private readonly correlation = new UtteranceCorrelationStore();
  private readonly router = new RealtimeEventRouter(this.correlation);
  private readonly realtimeClients = new Map<Source, RealtimeTranscriptionClient>();
  private activeClientUtteranceId: string | null = null;
  private activeSource: Source | null = null;
  private terminated = false;
  private closed = false;
  private readonly failedRealtimeSources = new Set<Source>();

  constructor(private readonly options: ClientSessionManagerOptions) {
    this.overlayResponses = new OverlayResponseService(options.overlayResponseClient);
  }

  async handleControl(message: ClientControlMessage): Promise<void> {
    if (this.terminated) {
      return;
    }

    switch (message.type) {
      case "hello":
        this.sessionId = message.session_id;
        this.send({
          type: "session_state",
          status: "ready",
          session_id: message.session_id
        });
        return;

      case "start_stream":
        if (message.source !== "microphone") {
          this.send({
            type: "recoverable_error",
            code: "source_unavailable",
            message: "System audio capture is not available in the P0 microphone build."
          });
          return;
        }

        if (!this.options.mockMode && this.options.realtimeClientFactory) {
          this.failedRealtimeSources.delete(message.source);
          this.realtimeClients.set(message.source, this.options.realtimeClientFactory(message));
        }
        return;

      case "utterance_start":
        if (message.source !== "microphone") {
          this.send({
            type: "recoverable_error",
            code: "source_unavailable",
            message: "System audio capture is not available in the P0 microphone build.",
            client_utterance_id: message.client_utterance_id
          });
          return;
        }

        if (this.activeClientUtteranceId && this.activeClientUtteranceId !== message.client_utterance_id) {
          this.failAmbiguousAudioRouting();
          return;
        }

        const enqueueResult = this.correlation.enqueue({
          clientUtteranceId: message.client_utterance_id,
          sequence: message.sequence,
          source: message.source,
          speaker: message.speaker,
          startedAtMs: message.started_at_ms
        });
        if (enqueueResult === "duplicate") {
          return;
        }
        if (enqueueResult === "conflict") {
          this.sendFatalAndTerminate("protocol_violation", "Conflicting duplicate utterance_start.");
          return;
        }

        this.activeClientUtteranceId = message.client_utterance_id;
        this.activeSource = message.source;
        return;

      case "utterance_commit":
        if (
          this.activeClientUtteranceId &&
          this.activeClientUtteranceId !== message.client_utterance_id
        ) {
          this.send({
            type: "recoverable_error",
            code: "utterance_not_active",
            message: "The committed utterance is not the active microphone utterance.",
            client_utterance_id: message.client_utterance_id
          });
          return;
        }

        const commit = this.correlation.requestCommit(
          message.client_utterance_id,
          message.sequence,
          message.ended_at_ms
        );
        if (!commit.ok) {
          this.send({
            type: "recoverable_error",
            code: commit.code === "not_found" ? "unknown_utterance" : "utterance_not_committable",
            message: "The utterance is not active and cannot be committed.",
            client_utterance_id: message.client_utterance_id
          });
          return;
        }

        if (commit.duplicate) {
          return;
        }

        if (this.options.mockMode) {
          await this.emitMockCompletion(message.client_utterance_id, message.sequence, message.ended_at_ms);
        } else {
          this.realtimeClients.get(commit.utterance.source)?.commit();
        }
        if (this.activeClientUtteranceId === message.client_utterance_id) {
          this.activeClientUtteranceId = null;
          this.activeSource = null;
        }
        return;

      case "utterance_cancel": {
        if (
          this.activeClientUtteranceId &&
          this.activeClientUtteranceId !== message.client_utterance_id
        ) {
          this.sendFatalAndTerminate("protocol_violation", "Cancel referenced a different active utterance.");
          return;
        }

        const cancel = this.correlation.cancel(
          message.client_utterance_id,
          message.reason,
          message.sequence
        );
        if (!cancel.ok) {
          if (cancel.code === "not_found") {
            return;
          }
          this.send({
            type: "recoverable_error",
            code: "utterance_not_cancellable",
            message: "The utterance could not be cancelled safely.",
            client_utterance_id: message.client_utterance_id
          });
          return;
        }

        if (!cancel.duplicate && !this.options.mockMode) {
          this.realtimeClients.get(cancel.utterance.source)?.clear();
        }
        if (this.activeClientUtteranceId === message.client_utterance_id) {
          this.activeClientUtteranceId = null;
          this.activeSource = null;
        }
        return;
      }

      case "stop_stream":
        const stopped = this.correlation.clearUnfinishedForSource(message.source, "user_interrupted");
        if (this.activeSource === message.source) {
          this.activeClientUtteranceId = null;
          this.activeSource = null;
        }
        const client = this.realtimeClients.get(message.source);
        if (client && stopped.cancelled.length > 0) {
          client.clear();
        }
        client?.close();
        this.realtimeClients.delete(message.source);
        return;
    }
  }

  handleAudio(data: RawData | Buffer): void {
    if (this.terminated || this.options.mockMode || !this.activeClientUtteranceId) {
      return;
    }

    if (!this.activeSource) {
      return;
    }
    const buffer = rawDataToBuffer(data);
    try {
      this.realtimeClients.get(this.activeSource)?.appendAudio(buffer);
    } catch {
      this.sendFatalAndTerminate(
        "realtime_session_failed",
        "The transcription session ended and must be restarted."
      );
    }
  }

  async handleRealtimeEvent(event: Parameters<RealtimeEventRouter["route"]>[0]): Promise<void> {
    if (this.terminated) {
      return;
    }

    const routed = this.router.route(event);
    if (!routed) {
      return;
    }

    this.send(routed);
    if (routed.type === "transcript_completed") {
      await this.createOverlayResult(routed.openai_item_id, routed.transcript);
    }
  }

  handleRealtimeDisconnect(source?: Source): void {
    this.handleRealtimeFailure(source ?? "microphone", {
      source: source ?? "microphone",
      code: "openai_realtime_disconnected",
      message: "Transcription disconnected. The interrupted utterance was not committed or replayed.",
      interruptedUtterance: true
    });
  }

  handleRealtimeFailure(source: Source, failure: RealtimeTerminalFailure): void {
    const client = this.realtimeClients.get(source);
    const hadClient = this.realtimeClients.delete(source);
    const interruptedUtterance =
      this.activeSource === source ? this.activeClientUtteranceId ?? undefined : undefined;
    const cleared = this.correlation.clearUnfinishedForSource(source, "capture_interrupted");
    if (!hadClient && !interruptedUtterance && cleared.cancelled.length === 0 && cleared.abandoned.length === 0) {
      if (this.failedRealtimeSources.has(source)) {
        return;
      }
    }
    this.failedRealtimeSources.add(source);
    client?.close();

    if (this.activeSource === source) {
      this.activeClientUtteranceId = null;
      this.activeSource = null;
    }
    if (interruptedUtterance) {
      this.send({
        type: "recoverable_error",
        code: failure.code,
        message: failure.message,
        client_utterance_id: interruptedUtterance
      });
    }
    this.sendFatalAndTerminate(
      "realtime_session_failed",
      "The transcription session ended and must be restarted."
    );
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    for (const [source, client] of this.realtimeClients) {
      const cleared = this.correlation.clearUnfinishedForSource(source, "application_shutdown");
      if (cleared.cancelled.length > 0) {
        client.clear();
      }
      client.close();
    }
    this.realtimeClients.clear();
    this.activeClientUtteranceId = null;
    this.activeSource = null;
  }

  private failAmbiguousAudioRouting(): void {
    if (this.activeSource) {
      const client = this.realtimeClients.get(this.activeSource);
      const cleared = this.correlation.clearUnfinishedForSource(this.activeSource, "capture_interrupted");
      if (cleared.cancelled.length > 0) {
        client?.clear();
      }
      client?.close();
      this.realtimeClients.delete(this.activeSource);
    }
    this.activeClientUtteranceId = null;
    this.activeSource = null;
    this.sendFatalAndTerminate(
      "ambiguous_audio_routing",
      "The audio stream entered an ambiguous utterance state."
    );
  }

  private sendFatalAndTerminate(code: string, message: string): void {
    if (this.terminated) {
      return;
    }
    this.terminated = true;
    this.send({ type: "fatal_error", code, message });
    this.options.terminate?.();
  }

  private send(message: ServerMessage): boolean {
    return this.options.send(message) !== false;
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
      this.send(delta);
    }

    const completed = this.router.route({
      type: "conversation.item.input_audio_transcription.completed",
      item_id: itemId,
      transcript
    });
    if (completed) {
      this.send(completed);
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
    if (this.terminated || !correlated || !this.sessionId) {
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
    this.dialogue.addSpeechTurn({
      speaker: envelope.speaker,
      text: envelope.source_text,
      sequence: envelope.sequence
    });

    try {
      const result = await this.overlayResponses.translate(envelope);
      if (this.terminated) {
        return;
      }
      if (result.reply_needed) {
        this.dialogue.addSuggestedReply({
          suggestedReplyRu: result.suggested_reply_ru,
          suggestedReplyEn: result.suggested_reply_en,
          sequence: envelope.sequence
        });
      }
      this.send({
        type: "overlay_result",
        client_utterance_id: envelope.client_utterance_id,
        sequence: envelope.sequence,
        result
      });
    } catch (error) {
      if (this.terminated) {
        return;
      }
      this.send({
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
