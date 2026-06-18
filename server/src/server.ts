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
    const manager = new ClientSessionManager({
      mockMode: config.mockOpenAI,
      overlayResponseClient,
      send: (message) => ws.send(JSON.stringify(message)),
      terminate: () => ws.close(1008, "ambiguous_audio_routing"),
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
              ws.send(
                JSON.stringify({
                  type: "recoverable_error",
                  code: "realtime_event_routing_failed",
                  message: "Transcription event routing failed safely."
                })
              );
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
          ws.send(
            JSON.stringify({
              type: "recoverable_error",
              code: "audio_frame_too_large",
              message: "Audio frame exceeded the maximum size."
            })
          );
          return;
        }
        manager.handleAudio(data);
        return;
      }

      if (isOversizedControlMessage(data)) {
        ws.send(
          JSON.stringify({
            type: "fatal_error",
            code: "message_too_large",
            message: "Control message exceeded the maximum size."
          })
        );
        ws.close();
        return;
      }

      try {
        const parsedJson = JSON.parse(data.toString());
        const parsed = parseClientControlMessage(parsedJson);
        if (!parsed.ok) {
          ws.send(JSON.stringify({ type: "fatal_error", ...parsed.error }));
          ws.close();
          return;
        }

        void manager.handleControl(parsed.value).catch((error: unknown) => {
          logger.warn(
            { event: redactForLog({ error: error instanceof Error ? error.message : String(error) }) },
            "Client control handling failed"
          );
          ws.send(
            JSON.stringify({
              type: "fatal_error",
              code: "internal_control_error",
              message: "The session entered an unsafe protocol state."
            })
          );
          ws.close(1011, "internal_control_error");
        });
      } catch {
        ws.send(
          JSON.stringify({
            type: "fatal_error",
            code: "protocol_violation",
            message: "Malformed client message."
          })
        );
        ws.close();
      }
    });

    ws.on("close", () => manager.close());
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
