import WebSocket from "ws";
import type { Source } from "../protocol/schemas.js";
import type { OpenAIRealtimeEvent } from "./RealtimeEventRouter.js";

export interface RealtimeTranscriptionClient {
  appendAudio(pcm: Buffer): void;
  commit(): void;
  close(): void;
}

export interface RealtimeTranscriptionClientOptions {
  apiKey: string;
  model: string;
  delay: string;
  source: Source;
  languageHint: string | null;
  onEvent: (event: OpenAIRealtimeEvent) => void;
  onError: (error: Error) => void;
  onDisconnect: () => void;
}

export class OpenAIRealtimeTranscriptionClient implements RealtimeTranscriptionClient {
  private readonly socket: WebSocket;

  constructor(private readonly options: RealtimeTranscriptionClientOptions) {
    const url = `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(options.model)}`;
    this.socket = new WebSocket(url, {
      headers: {
        Authorization: `Bearer ${options.apiKey}`
      }
    });

    this.socket.on("open", () => this.configureSession());
    this.socket.on("message", (data) => this.handleMessage(data));
    this.socket.on("error", (error) => options.onError(error));
    this.socket.on("close", () => options.onDisconnect());
  }

  appendAudio(pcm: Buffer): void {
    this.send({
      type: "input_audio_buffer.append",
      audio: pcm.toString("base64")
    });
  }

  commit(): void {
    this.send({ type: "input_audio_buffer.commit" });
  }

  close(): void {
    this.socket.close();
  }

  private configureSession(): void {
    const transcription: Record<string, unknown> = {
      model: this.options.model,
      delay: this.options.delay
    };
    if (this.options.languageHint) {
      transcription.language = this.options.languageHint;
    }

    this.send({
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

  private handleMessage(data: WebSocket.RawData): void {
    try {
      this.options.onEvent(JSON.parse(data.toString()) as OpenAIRealtimeEvent);
    } catch (error) {
      this.options.onError(error instanceof Error ? error : new Error(String(error)));
    }
  }

  private send(event: unknown): void {
    if (this.socket.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify(event));
    }
  }
}
