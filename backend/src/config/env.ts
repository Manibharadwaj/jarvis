import "dotenv/config";
import z from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string(),
  REDIS_URL: z.string(),
  JWT_SECRET: z.string().min(8),
  LIVEKIT_URL: z.string().default("ws://localhost:7880"),
  LIVEKIT_API_KEY: z.string().default("devkey"),
  LIVEKIT_API_SECRET: z.string().default("devsecret"),
  LLM_API_KEY: z.string().default(""),
  LLM_BASE_URL: z.string().default("https://api.groq.com/openai/v1"),
  LLM_MODEL: z.string().default("llama-3.1-8b-instant"),
  EMBEDDING_MODEL: z.string().default("text-embedding-ada-002"),
});

export const env = envSchema.parse(process.env);
