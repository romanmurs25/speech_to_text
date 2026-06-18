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

  it("queues append, clear, append, and commit in exact order before readiness", () => {
    const socket = new FakeRealtimeSocket();
    const errors: string[] = [];
    const client = new OpenAIRealtimeTranscriptionClient({
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

    client.appendAudio(Buffer.from([1]));
    client.clear();
    client.appendAudio(Buffer.from([2]));
    client.commit();
    socket.open();
    socket.message({ type: "session.updated" });

    expect(socket.sent.map((value) => value.type)).toEqual([
      "session.update",
      "input_audio_buffer.append",
      "input_audio_buffer.clear",
      "input_audio_buffer.append",
      "input_audio_buffer.commit"
    ]);
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
    expect(socket.closed).toBe(true);
    expect(socket.sent).toEqual([]);
  });

  it("treats readiness queue overflow as terminal and ignores late session.updated", () => {
    const socket = new FakeRealtimeSocket();
    const terminalFailures: string[] = [];
    const events: unknown[] = [];
    const client = new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => socket,
      maxQueuedEvents: 1,
      onEvent: (event) => events.push(event),
      onError: () => {},
      onDisconnect: () => terminalFailures.push("disconnect"),
      onTerminalFailure: (failure) => terminalFailures.push(failure.code)
    });

    client.appendAudio(Buffer.from([1]));
    client.commit();
    socket.open();
    socket.message({ type: "session.updated" });
    client.appendAudio(Buffer.from([2]));

    expect(terminalFailures).toEqual(["realtime_queue_overflow"]);
    expect(socket.closed).toBe(true);
    expect(events).toEqual([]);
    expect(socket.sent).toEqual([]);
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

  it("treats OpenAI error events as terminal and uses safe messages", () => {
    const socket = new FakeRealtimeSocket();
    const errors: string[] = [];
    const terminalFailures: string[] = [];
    new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => socket,
      onEvent: () => {},
      onError: (error) => errors.push(error.message),
      onDisconnect: () => {},
      onTerminalFailure: (failure) => terminalFailures.push(failure.code)
    });

    socket.message({
      type: "error",
      error: { message: "input audio format rejected" }
    });

    expect(errors).toEqual(["input audio format rejected"]);
    expect(terminalFailures).toEqual(["openai_realtime_error"]);
  });

  it("treats malformed JSON as terminal for the current Realtime session", () => {
    const socket = new FakeRealtimeSocket();
    const terminalFailures: string[] = [];
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
      onDisconnect: () => terminalFailures.push("disconnect"),
      onTerminalFailure: (failure) => terminalFailures.push(failure.code)
    });

    socket.messageRaw("{");
    socket.closeFromServer();

    expect(errors[0]).toContain("Malformed Realtime message");
    expect(terminalFailures).toEqual(["openai_realtime_malformed_event"]);
    expect(socket.closed).toBe(true);
  });

  it("treats send failure during queued flush as terminal without dropping unsent events first", () => {
    const socket = new FakeRealtimeSocket();
    const terminalFailures: string[] = [];
    const errors: string[] = [];
    const client = new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => socket,
      onEvent: () => {},
      onError: (error) => errors.push(error.message),
      onDisconnect: () => terminalFailures.push("disconnect"),
      onTerminalFailure: (failure) => terminalFailures.push(failure.code)
    });

    client.appendAudio(Buffer.from([1]));
    client.commit();
    socket.open();
    socket.throwOnSendType = "input_audio_buffer.append";

    expect(() => socket.message({ type: "session.updated" })).not.toThrow();

    expect(errors).toEqual(["Realtime socket send failed."]);
    expect(terminalFailures).toEqual(["openai_realtime_send_failed"]);
    expect(socket.closed).toBe(true);
    expect(socket.sent.map((value) => value.type)).toEqual(["session.update"]);
  });

  it("treats send failure during ordinary append as terminal once", () => {
    const socket = new FakeRealtimeSocket();
    const terminalFailures: string[] = [];
    const errors: string[] = [];
    const client = new OpenAIRealtimeTranscriptionClient({
      apiKey: "test-key",
      model: "gpt-realtime-whisper",
      delay: "low",
      source: "microphone",
      languageHint: null,
      socketFactory: () => socket,
      onEvent: () => {},
      onError: (error) => errors.push(error.message),
      onDisconnect: () => terminalFailures.push("disconnect"),
      onTerminalFailure: (failure) => terminalFailures.push(failure.code)
    });

    socket.open();
    socket.message({ type: "session.updated" });
    socket.throwOnSendType = "input_audio_buffer.append";

    expect(() => client.appendAudio(Buffer.from([1, 2]))).not.toThrow();
    socket.closeFromServer();

    expect(errors).toEqual(["Realtime socket send failed."]);
    expect(terminalFailures).toEqual(["openai_realtime_send_failed"]);
  });
});

class FakeRealtimeSocket extends EventEmitter implements RealtimeSocket {
  readyState = 0;
  sent: Array<Record<string, unknown>> = [];
  closed = false;
  throwOnSendType: string | undefined;

  send(data: string): void {
    const parsed = JSON.parse(data) as Record<string, unknown>;
    if (parsed.type === this.throwOnSendType) {
      throw new Error("boom");
    }
    this.sent.push(parsed);
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
