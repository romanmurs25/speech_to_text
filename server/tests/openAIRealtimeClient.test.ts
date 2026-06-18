import { EventEmitter } from "node:events";
import { describe, expect, it } from "vitest";
import {
  OpenAIRealtimeTranscriptionClient,
  type RealtimeSocket
} from "../src/openai/OpenAIRealtimeTranscriptionClient.js";

describe("OpenAIRealtimeTranscriptionClient", () => {
  it("queues append and commit until the Realtime session is ready", () => {
    const socket = new FakeRealtimeSocket();
    const events: unknown[] = [];
    const errors: string[] = [];

    const client = new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => socket,
      onEvent: (event) => events.push(event),
      onError: (error) => errors.push(error.message),
      onDisconnect: () => errors.push("disconnect")
    });

    client.appendAudio(Buffer.from([1, 2, 3, 4]));
    client.commit();

    expect(socket.sent).toEqual([]);

    socket.open();
    expect(socket.sent.map((value) => value.type)).toEqual(["session.update"]);

    socket.message({ type: "session.updated" });
    expect(socket.sent.map((value) => value.type)).toEqual([
      "session.update",
      "input_audio_buffer.append",
      "input_audio_buffer.commit"
    ]);
    expect(socket.sent[1]).toMatchObject({ audio: Buffer.from([1, 2, 3, 4]).toString("base64") });
    expect(events).toEqual([{ type: "session.updated" }]);
    expect(errors).toEqual([]);
  });

  it("surfaces readiness queue overflow instead of silently dropping audio", () => {
    const socket = new FakeRealtimeSocket();
    const errors: string[] = [];
    const client = new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => socket,
      maxQueuedEvents: 1,
      onEvent: () => {},
      onError: (error) => errors.push(error.message),
      onDisconnect: () => {}
    });

    client.appendAudio(Buffer.from([1]));
    client.commit();
    socket.open();
    socket.message({ type: "session.updated" });

    expect(errors).toEqual(["Realtime readiness queue overflow."]);
    expect(socket.sent.map((value) => value.type)).toEqual(["session.update"]);
  });

  it("distinguishes intentional close from unexpected disconnect", () => {
    const intentionalSocket = new FakeRealtimeSocket();
    let intentionalDisconnects = 0;
    const intentional = new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => intentionalSocket,
      onEvent: () => {},
      onError: () => {},
      onDisconnect: () => {
        intentionalDisconnects += 1;
      }
    });

    intentional.close();
    expect(intentionalSocket.closed).toBe(true);
    expect(intentionalDisconnects).toBe(0);

    const unexpectedSocket = new FakeRealtimeSocket();
    let unexpectedDisconnects = 0;
    new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => unexpectedSocket,
      onEvent: () => {},
      onError: () => {},
      onDisconnect: () => {
        unexpectedDisconnects += 1;
      }
    });

    unexpectedSocket.closeFromServer();
    expect(unexpectedDisconnects).toBe(1);
  });

  it("handles malformed JSON and OpenAI error events explicitly", () => {
    const socket = new FakeRealtimeSocket();
    const errors: string[] = [];
    new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => socket,
      onEvent: () => {},
      onError: (error) => errors.push(error.message),
      onDisconnect: () => {}
    });

    socket.messageRaw("{");
    socket.message({
      type: "error",
      error: { message: "input audio format rejected" }
    });

    expect(errors[0]).toContain("JSON");
    expect(errors[1]).toBe("input audio format rejected");
  });
});

class FakeRealtimeSocket extends EventEmitter implements RealtimeSocket {
  readyState = 0;
  sent: Array<Record<string, unknown>> = [];
  closed = false;

  send(data: string): void {
    this.sent.push(JSON.parse(data) as Record<string, unknown>);
  }

  close(): void {
    this.closed = true;
    this.readyState = 3;
    this.emit("close");
  }

  open(): void {
    this.readyState = 1;
    this.emit("open");
  }

  closeFromServer(): void {
    this.readyState = 3;
    this.emit("close");
  }

  message(value: unknown): void {
    this.messageRaw(JSON.stringify(value));
  }

  messageRaw(value: string): void {
    this.emit("message", Buffer.from(value));
  }
}
