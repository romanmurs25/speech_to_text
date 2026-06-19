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
import { SafeClientWebSocketSession } from "./ws/safeWebSocket.js";

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
    let session: SafeClientWebSocketSession;
    const manager = new ClientSessionManager({
      mockMode: config.mockOpenAI,
      overlayResponseClient,
      send: (message) => session.send(message),
      terminate: () => {
        session.close(1008, "session_terminated");
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
              session.send({
                type: "recoverable_error",
                code: "realtime_event_routing_failed",
                message: "Transcription event routing failed safely."
              });
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
    session = new SafeClientWebSocketSession({
      socket: ws,
      logger,
      closeManager: () => {
        manager.close();
      }
    });

    ws.on("message", (data, isBinary) => {
      if (isBinary) {
        if (isOversizedAudioFrame(data)) {
          session.send({
            type: "recoverable_error",
            code: "audio_frame_too_large",
            message: "Audio frame exceeded the maximum size."
          });
          return;
        }
        try {
          manager.handleAudio(data);
        } catch (error) {
          logger.warn(
              { event: redactForLog({ error: error instanceof Error ? error.message : String(error) }) },
              "Binary audio handling failed"
            );
          session.send({
            type: "fatal_error",
            code: "realtime_session_failed",
            message: "The transcription session ended and must be restarted."
          });
          session.close(1011, "audio_append_failed");
        }
        return;
      }

      if (isOversizedControlMessage(data)) {
        session.send({
          type: "fatal_error",
          code: "message_too_large",
          message: "Control message exceeded the maximum size."
        });
        session.close();
        return;
      }

      try {
        const parsedJson = JSON.parse(data.toString());
        const parsed = parseClientControlMessage(parsedJson);
        if (!parsed.ok) {
          session.send({ type: "fatal_error", ...parsed.error });
          session.close();
          return;
        }

        void manager.handleControl(parsed.value).catch((error: unknown) => {
          logger.warn(
            { event: redactForLog({ error: error instanceof Error ? error.message : String(error) }) },
            "Client control handling failed"
          );
          session.send({
            type: "fatal_error",
            code: "internal_control_error",
            message: "The session entered an unsafe protocol state."
          });
          session.close(1011, "internal_control_error");
        });
      } catch {
        session.send({
          type: "fatal_error",
          code: "protocol_violation",
          message: "Malformed client message."
        });
        session.close();
      }
    });
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
