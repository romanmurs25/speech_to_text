import WebSocket, { type RawData } from "ws";
import type { Source } from "../protocol/schemas.js";
import type { OpenAIRealtimeEvent } from "./RealtimeEventRouter.js";

export interface RealtimeTranscriptionClient {
  appendAudio(pcm: Buffer): void;
  commit(): void;
  clear(): void;
  close(): void;
}

export interface RealtimeSocket {
  readonly readyState: number;
  send(data: string): void;
  close(): void;
  on(event: "open", listener: () => void): void;
  on(event: "message", listener: (data: RawData) => void): void;
  on(event: "error", listener: (error: Error) => void): void;
  on(event: "close", listener: () => void): void;
}

export type RealtimeSocketFactory = (
  url: string,
  options: { headers: Record<string, string> }
) => RealtimeSocket;

export interface RealtimeTranscriptionClientOptions {
  apiKey: string;
  model: string;
  delay: string;
  source: Source;
  languageHint: string | null;
  onEvent: (event: OpenAIRealtimeEvent) => void;
  onError: (error: Error) => void;
  onDisconnect: () => void;
  onTerminalFailure?: (failure: RealtimeTerminalFailure) => void;
  socketFactory?: RealtimeSocketFactory;
  maxQueuedEvents?: number;
  maxQueuedAudioBytes?: number;
}

export interface RealtimeTerminalFailure {
  source: Source;
  code: string;
  message: string;
  interruptedUtterance: boolean;
}

type RealtimeClientState =
  | "connecting"
  | "configuring"
  | "ready"
  | "intentionallyClosing"
  | "disconnected"
  | "failed";

export class OpenAIRealtimeTranscriptionClient implements RealtimeTranscriptionClient {
  private readonly socket: RealtimeSocket;
  private readonly maxQueuedEvents: number;
  private readonly maxQueuedAudioBytes: number;
  private readonly queuedEvents: Array<{ event: unknown; audioBytes: number }> = [];
  private queuedAudioBytes = 0;
  private state: RealtimeClientState = "connecting";
  private terminalNotified = false;
  private closeRequested = false;

  constructor(private readonly options: RealtimeTranscriptionClientOptions) {
    const url = `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(options.model)}`;
    const socketFactory =
      options.socketFactory ??
      ((socketUrl, socketOptions) => new WebSocket(socketUrl, socketOptions));
    this.socket = socketFactory(url, {
      headers: {
        Authorization: `Bearer ${options.apiKey}`
      }
    });
    this.maxQueuedEvents = options.maxQueuedEvents ?? 128;
    this.maxQueuedAudioBytes = options.maxQueuedAudioBytes ?? 4 * 1024 * 1024;

    this.socket.on("open", () => this.configureSession());
    this.socket.on("message", (data) => this.handleMessage(data));
    this.socket.on("error", (error) => {
      this.failTerminal("openai_realtime_error", error.message);
    });
    this.socket.on("close", () => this.handleClose());
  }

  appendAudio(pcm: Buffer): void {
    this.sendWhenReady({
      type: "input_audio_buffer.append",
      audio: pcm.toString("base64")
    }, pcm.length);
  }

  commit(): void {
    this.sendWhenReady({ type: "input_audio_buffer.commit" });
  }

  clear(): void {
    this.sendWhenReady({ type: "input_audio_buffer.clear" });
  }

  close(): void {
    if (
      this.state === "disconnected" ||
      this.state === "intentionallyClosing" ||
      (this.state === "failed" && this.closeRequested)
    ) {
      return;
    }
    if (this.state === "failed") {
      this.requestSocketClose();
      return;
    }
    this.state = "intentionallyClosing";
    this.requestSocketClose();
  }

  private configureSession(): void {
    if (this.state !== "connecting") {
      return;
    }
    this.state = "configuring";
    const transcription: Record<string, unknown> = {
      model: this.options.model,
      delay: this.options.delay
    };
    if (this.options.languageHint) {
      transcription.language = this.options.languageHint;
    }

    this.sendImmediately({
      type: "session.update",
      session: {
        type: "transcription",
        audio: {
          input: {
            format: {
              type: "audio/pcm",
              rate: 24000
            },
            transcription,
            turn_detection: null
          }
        }
      }
    });
  }

  private handleMessage(data: RawData): void {
    try {
      const event = JSON.parse(data.toString()) as OpenAIRealtimeEvent;
      if (event.type === "session.updated") {
        if (this.state !== "configuring") {
          return;
        }
        this.state = "ready";
        this.options.onEvent(event);
        this.flushQueuedEvents();
        return;
      }

      if (event.type === "error") {
        this.failTerminal("openai_realtime_error", readRealtimeErrorMessage(event));
        return;
      }

      this.options.onEvent(event);
    } catch (error) {
      this.failTerminal(
        "openai_realtime_malformed_event",
        "Malformed Realtime message."
      );
    }
  }

  private sendWhenReady(event: unknown, audioBytes = 0): void {
    if (this.state === "ready") {
      this.sendImmediately(event);
      return;
    }

    if (this.state === "connecting" || this.state === "configuring") {
      this.enqueueEvent(event, audioBytes);
      return;
    }

    this.options.onError(new Error("Realtime transcription is not connected."));
  }

  private enqueueEvent(event: unknown, audioBytes: number): void {
    if (
      this.queuedEvents.length >= this.maxQueuedEvents ||
      this.queuedAudioBytes + audioBytes > this.maxQueuedAudioBytes
    ) {
      this.failTerminal(
        "realtime_queue_overflow",
        "Realtime readiness queue overflow."
      );
      return;
    }

    this.queuedEvents.push({ event, audioBytes });
    this.queuedAudioBytes += audioBytes;
  }

  private flushQueuedEvents(): void {
    while (this.queuedEvents.length > 0 && this.state === "ready") {
      const queued = this.queuedEvents[0];
      if (!queued) {
        return;
      }
      if (!this.sendImmediately(queued.event)) {
        return;
      }
      this.queuedEvents.shift();
      this.queuedAudioBytes -= queued.audioBytes;
    }
  }

  private sendImmediately(event: unknown): boolean {
    if (this.socket.readyState === WebSocket.OPEN) {
      try {
        this.socket.send(JSON.stringify(event));
        return true;
      } catch {
        this.failTerminal("openai_realtime_send_failed", "Realtime socket send failed.");
        return false;
      }
    }

    this.failTerminal("openai_realtime_send_failed", "Realtime socket is not open.");
    return false;
  }

  private handleClose(): void {
    if (this.state === "disconnected") {
      return;
    }
    const wasIntentional = this.state === "intentionallyClosing";
    const wasFailed = this.state === "failed";
    this.state = "disconnected";
    this.clearQueue();
    if (!wasIntentional && !wasFailed) {
      this.options.onDisconnect();
    }
  }

  private failTerminal(code: string, message: string): void {
    if (this.state === "failed" || this.state === "disconnected" || this.state === "intentionallyClosing") {
      return;
    }

    this.state = "failed";
    this.clearQueue();
    const error = new Error(message);
    this.options.onError(error);
    if (!this.terminalNotified) {
      this.terminalNotified = true;
      this.options.onTerminalFailure?.({
        source: this.options.source,
        code,
        message,
        interruptedUtterance: true
      });
    }
    this.requestSocketClose();
  }

  private clearQueue(): void {
    this.queuedEvents.length = 0;
    this.queuedAudioBytes = 0;
  }

  private requestSocketClose(): void {
    if (this.closeRequested) {
      return;
    }
    this.closeRequested = true;
    this.socket.close();
  }
}

function readRealtimeErrorMessage(event: OpenAIRealtimeEvent): string {
  const error = "error" in event && typeof event.error === "object" ? event.error : null;
  if (error && "message" in error && typeof error.message === "string") {
    return error.message;
  }
  return "OpenAI Realtime reported an error.";
}
