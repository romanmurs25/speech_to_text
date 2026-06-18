import { describe, expect, it, vi } from "vitest";
import { safeClose, safeSend } from "../src/ws/safeWebSocket.js";

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
