export interface ServerConfig {
  host: string;
  port: number;
  mockOpenAI: boolean;
  openAIApiKey: string | undefined;
  openAITextModel: string;
  openAIRealtimeModel: string;
  logLevel: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): ServerConfig {
  return {
    host: env.HOST ?? "127.0.0.1",
    port: Number(env.PORT ?? 8787),
    mockOpenAI: (env.MOCK_OPENAI ?? "true").toLowerCase() !== "false",
    openAIApiKey: env.OPENAI_API_KEY,
    openAITextModel: env.OPENAI_TEXT_MODEL ?? "gpt-5.4-mini",
    openAIRealtimeModel: env.OPENAI_REALTIME_MODEL ?? "gpt-realtime-whisper",
    logLevel: env.LOG_LEVEL ?? "info"
  };
}
