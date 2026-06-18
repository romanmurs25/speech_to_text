import pino from "pino";
import { redactForLog } from "./redaction.js";

export function createLogger(level = "info") {
  return pino({
    level,
    serializers: {
      event: redactForLog,
      err: pino.stdSerializers.err
    },
    redact: {
      paths: ["authorization", "Authorization", "OPENAI_API_KEY", "*.OPENAI_API_KEY"],
      censor: "[REDACTED_SECRET]"
    }
  });
}
