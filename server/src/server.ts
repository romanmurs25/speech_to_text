import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
import WebSocket, { WebSocketServer } from "ws";
import { loadConfig, type ServerConfig } from "./config/env.js";
import { createLogger } from "./logging/logger.js";
import { redactForLog } from "./logging/redaction.js";
import { parseClientControlMessage } from "./protocol/schemas.js";
import { MockOpenAIResponsesClient } from "./openai/MockOpenAIResponsesClient.js";
import { OpenAIResponsesClient } from "./openai/OpenAIResponsesClient.js";
import { OpenAIRealtimeTranscriptionClient } from "./openai/OpenAIRealtimeTranscriptionClient.js";
import { ClientSessionManager } from "./ws/ClientSessionManager.js";
import {
  MAX_AUDIO_FRAME_BYTES,
  isOversizedAudioFrame,
  isOversizedControlMessage
} from "./ws/messageLimits.js";
import { safeClose, safeSend } from "./ws/safeWebSocket.js";

export async function createApp(config: ServerConfig = loadConfig()) {
  const openAIApiKey = config.openAIApiKey?.trim();
  if (!config.mockOpenAI && !openAIApiKey) {
    throw new Error("OPENAI_API_KEY is required when MOCK_OPENAI=false");
  }

  const logger = createLogger(config.logLevel);
  const app = Fastify({ loggerInstance: logger });

  await app.register(rateLimit, {
    max: 600,
    timeWindow: "1 minute"
  });

  app.get("/health", async () => ({
    ok: true,
    mockOpenAI: config.mockOpenAI
  }));

  const overlayResponseClient =
    config.mockOpenAI
      ? new MockOpenAIResponsesClient()
      : new OpenAIResponsesClient({
          apiKey: openAIApiKey ?? "",
          model: config.openAITextModel
        });

  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_AUDIO_FRAME_BYTES });

  app.server.on("upgrade", (request, socket, head) => {
    if (request.url !== "/ws") {
      socket.destroy();
      return;
    }

    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit("connection", ws, request);
    });
  });

  wss.on("connection", (ws: WebSocket) => {
    let managerClosed = false;
    const closeManagerOnce = () => {
      if (managerClosed) {
        return;
      }
      managerClosed = true;
      manager.close();
    };
    const manager = new ClientSessionManager({
      mockMode: config.mockOpenAI,
      overlayResponseClient,
      send: (message) => safeSend(ws, message, logger),
      terminate: () => {
        safeClose(ws, 1008, "session_terminated");
      },
      realtimeClientFactory: (message) => {
        return new OpenAIRealtimeTranscriptionClient({
          apiKey: openAIApiKey ?? "",
          model: config.openAIRealtimeModel,
          delay: config.openAIRealtimeDelay,
          source: message.source,
          languageHint: message.language_hint,
          onEvent: (event) => {
            void manager.handleRealtimeEvent(event).catch((error: unknown) => {
              logger.warn(
                { event: redactForLog({ error: error instanceof Error ? error.message : String(error) }) },
                "Realtime event routing error"
              );
              safeSend(ws, {
                type: "recoverable_error",
                code: "realtime_event_routing_failed",
                message: "Transcription event routing failed safely."
              }, logger);
            });
          },
          onError: (error) => {
            logger.warn({ event: redactForLog({ error: error.message }) }, "Realtime error");
          },
          onDisconnect: () => {
            manager.handleRealtimeDisconnect(message.source);
          },
          onTerminalFailure: (failure) => {
            manager.handleRealtimeFailure(message.source, failure);
          }
        });
      }
    });

    ws.on("message", (data, isBinary) => {
      if (isBinary) {
        if (isOversizedAudioFrame(data)) {
          safeSend(ws, {
            type: "recoverable_error",
            code: "audio_frame_too_large",
            message: "Audio frame exceeded the maximum size."
          }, logger);
          return;
        }
        try {
          manager.handleAudio(data);
        } catch (error) {
          logger.warn(
            { event: redactForLog({ error: error instanceof Error ? error.message : String(error) }) },
            "Binary audio handling failed"
          );
          safeSend(ws, {
            type: "fatal_error",
            code: "realtime_session_failed",
            message: "The transcription session ended and must be restarted."
          }, logger);
          safeClose(ws, 1011, "audio_append_failed");
        }
        return;
      }

      if (isOversizedControlMessage(data)) {
        safeSend(ws, {
          type: "fatal_error",
          code: "message_too_large",
          message: "Control message exceeded the maximum size."
        }, logger);
        safeClose(ws);
        return;
      }

      try {
        const parsedJson = JSON.parse(data.toString());
        const parsed = parseClientControlMessage(parsedJson);
        if (!parsed.ok) {
          safeSend(ws, { type: "fatal_error", ...parsed.error }, logger);
          safeClose(ws);
          return;
        }

        void manager.handleControl(parsed.value).catch((error: unknown) => {
          logger.warn(
            { event: redactForLog({ error: error instanceof Error ? error.message : String(error) }) },
            "Client control handling failed"
          );
          safeSend(ws, {
            type: "fatal_error",
            code: "internal_control_error",
            message: "The session entered an unsafe protocol state."
          }, logger);
          safeClose(ws, 1011, "internal_control_error");
        });
      } catch {
        safeSend(ws, {
          type: "fatal_error",
          code: "protocol_violation",
          message: "Malformed client message."
        }, logger);
        safeClose(ws);
      }
    });

    ws.on("close", closeManagerOnce);
  });

  app.addHook("onClose", async () => {
    wss.close();
  });

  return app;
}

export async function startServer(config: ServerConfig = loadConfig()): Promise<void> {
  const app = await createApp(config);
  await app.listen({ host: config.host, port: config.port });
}
