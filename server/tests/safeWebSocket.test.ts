import { EventEmitter } from "node:events";
import { describe, expect, it, vi } from "vitest";
import { SafeClientWebSocketSession, safeClose, safeSend } from "../src/ws/safeWebSocket.js";

describe("safe WebSocket helpers", () => {
  it("does not throw or send when the socket is closing", () => {
    const socket = new FakeWebSocket(2);

    expect(safeSend(socket, { type: "fatal_error", code: "closed", message: "closed" })).toBe(false);

    expect(socket.sent).toEqual([]);
  });

  it("catches synchronous send exceptions and reports a failed send", () => {
    const logger = { warn: vi.fn() };
    const socket = new FakeWebSocket(1);
    socket.throwOnSend = true;

    expect(safeSend(socket, { type: "fatal_error", code: "boom", message: "boom" }, logger)).toBe(false);

    expect(logger.warn).toHaveBeenCalledTimes(1);
  });

  it("closes at most once", () => {
    const socket = new FakeWebSocket(1);

    expect(safeClose(socket, 1008, "unsafe")).toBe(true);
    expect(safeClose(socket, 1008, "unsafe")).toBe(false);

    expect(socket.closeCalls).toBe(1);
  });

  it("terminalizes a client WebSocket error exactly once across error and close events", () => {
    const socket = new FakeEventWebSocket(1);
    const logger = { warn: vi.fn() };
    let managerCloses = 0;
    new SafeClientWebSocketSession({
      socket,
      logger,
      closeManager: () => {
        managerCloses += 1;
      }
    });

    socket.emit("error", new Error("client socket failed with secret-token"));
    socket.emit("close");

    expect(managerCloses).toBe(1);
    expect(socket.closeCalls).toBe(1);
    expect(logger.warn).toHaveBeenCalledTimes(1);
  });

  it("keeps close plus later error idempotent and suppresses sends after closing begins", () => {
    const socket = new FakeEventWebSocket(1);
    let managerCloses = 0;
    const session = new SafeClientWebSocketSession({
      socket,
      logger: { warn: vi.fn() },
      closeManager: () => {
        managerCloses += 1;
      }
    });

    socket.emit("close");
    socket.emit("error", new Error("late error"));

    expect(managerCloses).toBe(1);
    expect(session.send({ type: "session_state", status: "ready", session_id: "id" })).toBe(false);
    expect(socket.sent).toEqual([]);
  });
});

class FakeWebSocket {
  sent: string[] = [];
  closeCalls = 0;
  throwOnSend = false;

  constructor(public readyState: number) {}

  send(value: string): void {
    if (this.throwOnSend) {
      throw new Error("send failed");
    }
    this.sent.push(value);
  }

  close(_code?: number, _reason?: string): void {
    this.closeCalls += 1;
    this.readyState = 2;
  }
}

class FakeEventWebSocket extends EventEmitter {
  sent: string[] = [];
  closeCalls = 0;

  constructor(public readyState: number) {
    super();
  }

  send(value: string): void {
    this.sent.push(value);
  }

  close(_code?: number, _reason?: string): void {
    this.closeCalls += 1;
    this.readyState = 2;
  }
}
