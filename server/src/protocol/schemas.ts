import { z } from "zod";

export const ProtocolVersionSchema = z.literal(1);
export const SourceSchema = z.enum(["microphone", "systemAudio"]);
export const SpeakerSchema = z.enum(["local", "remote"]);
export const EncodingSchema = z.literal("pcm_s16le");

const ClientUtteranceIdSchema = z.string().min(1);
const SequenceSchema = z.number().int().nonnegative();
const TimestampMsSchema = z.number().int().nonnegative();

export const HelloMessageSchema = z.object({
  type: z.literal("hello"),
  protocol_version: ProtocolVersionSchema,
  client_version: z.string().min(1),
  session_id: z.string().uuid()
});

export const StartStreamMessageSchema = z.object({
  type: z.literal("start_stream"),
  source: SourceSchema,
  sample_rate: z.literal(24000),
  channels: z.literal(1),
  encoding: EncodingSchema,
  language_hint: z.string().regex(/^[a-z]{2}$/).nullable()
});

export const UtteranceStartMessageSchema = z
  .object({
    type: z.literal("utterance_start"),
    client_utterance_id: ClientUtteranceIdSchema,
    source: SourceSchema,
    speaker: SpeakerSchema,
    sequence: SequenceSchema,
    started_at_ms: TimestampMsSchema
  })
  .refine(
    (value) =>
      (value.source === "microphone" && value.speaker === "local") ||
      (value.source === "systemAudio" && value.speaker === "remote"),
    {
      message: "source and speaker do not match"
    }
  );

export const UtteranceCommitMessageSchema = z.object({
  type: z.literal("utterance_commit"),
  client_utterance_id: ClientUtteranceIdSchema,
  sequence: SequenceSchema,
  ended_at_ms: TimestampMsSchema
});

export const StopStreamMessageSchema = z.object({
  type: z.literal("stop_stream"),
  source: SourceSchema
});

export const ClientControlMessageSchema = z.discriminatedUnion("type", [
  HelloMessageSchema,
  StartStreamMessageSchema,
  UtteranceStartMessageSchema,
  UtteranceCommitMessageSchema,
  StopStreamMessageSchema
]);

export const DialogueTurnSchema = z.object({
  speaker: SpeakerSchema,
  text: z.string().min(1)
});

export const FinalUtteranceEnvelopeSchema = z.object({
  session_id: z.string().uuid(),
  utterance_id: z.string().min(1),
  client_utterance_id: ClientUtteranceIdSchema,
  sequence: SequenceSchema,
  speaker: SpeakerSchema,
  source: SourceSchema,
  started_at_ms: TimestampMsSchema,
  ended_at_ms: TimestampMsSchema,
  source_text: z.string().min(1),
  source_language_hint: z.string().regex(/^[a-z]{2}$/).nullable(),
  context: z.array(DialogueTurnSchema).max(12),
  reply_style: z.literal("concise_professional")
});

export const OverlayResultSchema = z.object({
  utterance_id: z.string(),
  detected_language: z.string(),
  original_text: z.string(),
  translation_ru: z.string(),
  translation_en: z.string(),
  reply_needed: z.boolean(),
  suggested_reply_ru: z.string(),
  suggested_reply_en: z.string()
});

export const SessionStateMessageSchema = z.object({
  type: z.literal("session_state"),
  status: z.enum(["connected", "ready", "degraded", "closed"]),
  session_id: z.string().uuid()
});

export const TranscriptDeltaMessageSchema = z.object({
  type: z.literal("transcript_delta"),
  client_utterance_id: ClientUtteranceIdSchema,
  openai_item_id: z.string(),
  sequence: SequenceSchema,
  source: SourceSchema,
  speaker: SpeakerSchema,
  delta: z.string()
});

export const TranscriptCompletedMessageSchema = z.object({
  type: z.literal("transcript_completed"),
  client_utterance_id: ClientUtteranceIdSchema,
  openai_item_id: z.string(),
  sequence: SequenceSchema,
  source: SourceSchema,
  speaker: SpeakerSchema,
  transcript: z.string()
});

export const OverlayResultMessageSchema = z.object({
  type: z.literal("overlay_result"),
  client_utterance_id: ClientUtteranceIdSchema,
  sequence: SequenceSchema,
  result: OverlayResultSchema
});

export const RecoverableErrorMessageSchema = z.object({
  type: z.literal("recoverable_error"),
  code: z.string(),
  message: z.string(),
  client_utterance_id: ClientUtteranceIdSchema.optional()
});

export const FatalErrorMessageSchema = z.object({
  type: z.literal("fatal_error"),
  code: z.string(),
  message: z.string()
});

export const ServerMessageSchema = z.discriminatedUnion("type", [
  SessionStateMessageSchema,
  TranscriptDeltaMessageSchema,
  TranscriptCompletedMessageSchema,
  OverlayResultMessageSchema,
  RecoverableErrorMessageSchema,
  FatalErrorMessageSchema
]);

export type ClientControlMessage = z.infer<typeof ClientControlMessageSchema>;
export type Source = z.infer<typeof SourceSchema>;
export type Speaker = z.infer<typeof SpeakerSchema>;
export type DialogueTurn = z.infer<typeof DialogueTurnSchema>;
export type FinalUtteranceEnvelope = z.infer<typeof FinalUtteranceEnvelopeSchema>;
export type OverlayResult = z.infer<typeof OverlayResultSchema>;
export type ServerMessage = z.infer<typeof ServerMessageSchema>;
export type TranscriptDeltaMessage = z.infer<typeof TranscriptDeltaMessageSchema>;
export type TranscriptCompletedMessage = z.infer<typeof TranscriptCompletedMessageSchema>;

export type ParseResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: { code: "protocol_violation"; message: "Malformed client message." } };

export function parseClientControlMessage(value: unknown): ParseResult<ClientControlMessage> {
  const parsed = ClientControlMessageSchema.safeParse(value);
  if (parsed.success) {
    return { ok: true, value: parsed.data };
  }

  return {
    ok: false,
    error: {
      code: "protocol_violation",
      message: "Malformed client message."
    }
  };
}
