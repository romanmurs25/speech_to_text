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
import { rawDataByteLength } from "./ws/rawData.js";

const MAX_JSON_BYTES = 64 * 1024;
const MAX_AUDIO_BYTES = 256 * 1024;

export async function createApp(config: ServerConfig = loadConfig()) {
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
    config.mockOpenAI || !config.openAIApiKey
      ? new MockOpenAIResponsesClient()
      : new OpenAIResponsesClient({
          apiKey: config.openAIApiKey,
          model: config.openAITextModel
        });

  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_AUDIO_BYTES });

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
      realtimeClientFactory: (message) => {
        if (!config.openAIApiKey) {
          throw new Error("OPENAI_API_KEY is required when MOCK_OPENAI=false");
        }
        return new OpenAIRealtimeTranscriptionClient({
          apiKey: config.openAIApiKey,
          model: config.openAIRealtimeModel,
          source: message.source,
          languageHint: message.language_hint,
          onEvent: (event) => {
            void manager.handleRealtimeEvent(event);
          },
          onError: (error) => {
            logger.warn({ event: redactForLog({ error: error.message }) }, "Realtime error");
            ws.send(
              JSON.stringify({
                type: "recoverable_error",
                code: "openai_realtime_error",
                message: "Transcription is temporarily unavailable."
              })
            );
          }
        });
      }
    });

    ws.on("message", (data, isBinary) => {
      if (isBinary) {
        if (rawDataByteLength(data) > MAX_AUDIO_BYTES) {
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

      if (rawDataByteLength(data) > MAX_JSON_BYTES) {
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

        void manager.handleControl(parsed.value);
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
