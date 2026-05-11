import { FastifyInstance } from "fastify";
import z from "zod";
import { pool } from "../config/database.js";
import { saveMemory, searchMemories, getMemoriesByType, deleteMemory } from "../services/memory.js";
import { getLatestEmotion, recordEmotion } from "../services/emotion.js";

const saveMemorySchema = z.object({
  type: z.enum(["fact", "preference", "goal_detail", "emotional_event", "inside_joke"]),
  content: z.string().min(1).max(5000),
  importance: z.number().min(0).max(1).default(0.5),
  confidence: z.number().min(0).max(1).default(0.5),
});

const searchMemorySchema = z.object({
  query: z.string().min(1),
  limit: z.number().min(1).max(50).default(5),
  min_importance: z.number().min(0).max(1).default(0),
});

export async function memoryRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.post("/api/v1/memories", async (req, reply) => {
    const body = saveMemorySchema.parse(req.body);
    const memory = await saveMemory(req.user.sub, body.type, body.content, body.importance, body.confidence);
    reply.code(201).send({ memory });
  });

  app.post("/api/v1/memories/search", async (req, reply) => {
    const body = searchMemorySchema.parse(req.body);
    const results = await searchMemories(req.user.sub, body.query, body.limit, body.min_importance);
    reply.send({ results });
  });

  app.get("/api/v1/memories/:type", async (req, reply) => {
    const { type } = req.params as { type: string };
    const memories = await getMemoriesByType(req.user.sub, type as any);
    reply.send({ memories });
  });

  app.delete("/api/v1/memories/:id", async (req, reply) => {
    const { id } = req.params as { id: string };
    const deleted = await deleteMemory(req.user.sub, id);
    if (!deleted) {
      reply.code(404).send({ error: "Memory not found" });
      return;
    }
    reply.code(204).send();
  });

  app.post("/api/v1/memories/from-conversation", async (req, reply) => {
    const { conversation_id } = req.body as { conversation_id: string };
    const result = await pool.query(
      `SELECT content FROM messages WHERE conversation_id = $1 AND role = 'user' ORDER BY created_at DESC LIMIT 3`,
      [conversation_id]
    );
    for (const row of result.rows) {
      try {
        const emotion = await getLatestEmotion(req.user.sub);
        await saveMemory(req.user.sub, "emotional_event", row.content, 0.4);
        await recordEmotion(req.user.sub, emotion?.mood || "neutral");
      } catch {}
    }
    reply.send({ ok: true });
  });
}
