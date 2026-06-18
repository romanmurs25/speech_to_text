import { redactForLog } from "../logging/redaction.js";

interface SendableSocket {
  readonly readyState: number;
  send(data: string): void;
}

interface ClosableSocket {
  readonly readyState: number;
  close(code?: number, reason?: string): void;
}

interface WarningLogger {
  warn(payload: unknown, message?: string): void;
}

const OPEN = 1;
const CLOSING = 2;
const CLOSED = 3;

export function safeSend(
  socket: SendableSocket,
  message: unknown,
  logger?: WarningLogger
): boolean {
  if (socket.readyState !== OPEN) {
    return false;
  }

  try {
    socket.send(JSON.stringify(message));
    return true;
  } catch (error) {
    logger?.warn(
      { event: redactForLog({ error: error instanceof Error ? error.message : String(error) }) },
      "WebSocket send failed"
    );
    return false;
  }
}

export function safeClose(socket: ClosableSocket, code?: number, reason?: string): boolean {
  if (socket.readyState === CLOSING || socket.readyState === CLOSED) {
    return false;
  }

  try {
    socket.close(code, reason);
    return true;
  } catch {
    return false;
  }
}
