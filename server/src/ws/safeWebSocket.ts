import { redactForLog } from "../logging/redaction.js";

interface SendableSocket {
  readonly readyState: number;
  send(data: string): void;
}

interface ClosableSocket {
  readonly readyState: number;
  close(code?: number, reason?: string): void;
}

interface EventSocket extends SendableSocket, ClosableSocket {
  on(event: "close", listener: () => void): void;
  on(event: "error", listener: (error: Error) => void): void;
}

interface WarningLogger {
  warn(payload: unknown, message?: string): void;
}

const OPEN = 1;
const CLOSING = 2;
const CLOSED = 3;

export interface SafeClientWebSocketSessionOptions {
  socket: EventSocket;
  logger?: WarningLogger;
  closeManager: () => void;
}

export class SafeClientWebSocketSession {
  private closing = false;
  private managerClosed = false;

  constructor(private readonly options: SafeClientWebSocketSessionOptions) {
    options.socket.on("error", (error) => {
      this.handleError(error);
    });
    options.socket.on("close", () => {
      this.handleClose();
    });
  }

  send(message: unknown): boolean {
    if (this.closing) {
      return false;
    }
    return safeSend(this.options.socket, message, this.options.logger);
  }

  close(code?: number, reason?: string): boolean {
    this.closing = true;
    return safeClose(this.options.socket, code, reason);
  }

  closeManagerOnce(): void {
    if (this.managerClosed) {
      return;
    }
    this.managerClosed = true;
    this.options.closeManager();
  }

  private handleError(error: Error): void {
    this.closing = true;
    this.options.logger?.warn(
      { event: redactForLog({ error: error.message }) },
      "Client WebSocket error"
    );
    this.closeManagerOnce();
    this.close();
  }

  private handleClose(): void {
    this.closing = true;
    this.closeManagerOnce();
  }
}

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
