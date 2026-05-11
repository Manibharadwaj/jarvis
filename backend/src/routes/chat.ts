import { FastifyInstance } from "fastify";
import z from "zod";
import { pool } from "../config/database.js";
import { env } from "../config/env.js";

const chatSchema = z.object({
  message: z.string().min(1).max(2000),
  conversation_id: z.string().uuid().optional(),
});

async function callLLM(messages: { role: string; content: string }[]): Promise<string> {
  if (!env.LLM_API_KEY) {
    const last = messages.filter(m => m.role === "user").pop();
    const msg = last?.content.toLowerCase() || "";
    if (msg.includes("goal") || msg.includes("progress")) return "Keep pushing on your goals! Every day counts.";
    if (msg.includes("hello") || msg.includes("hey") || msg.includes("hi")) return "Hey! Good to hear from you. How are things going?";
    return "I hear you. Tell me more about how you're doing.";
  }

  const response = await fetch(`${env.LLM_BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.LLM_API_KEY}`,
    },
    body: JSON.stringify({
      model: env.LLM_MODEL,
      messages,
      temperature: 0.7,
      max_tokens: 150,
    }),
  });

  if (!response.ok) {
    return "I'm here. Tell me how you're doing.";
  }

  const data = (await response.json()) as any;
  return data.choices?.[0]?.message?.content || "Got it. Let's keep going.";
}

export async function chatRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.post("/api/v1/chat/message", async (req, reply) => {
    const body = chatSchema.parse(req.body);
    let convId = body.conversation_id;

    if (!convId) {
      const conv = await pool.query(
        `INSERT INTO conversations (user_id, call_type) VALUES ($1, 'chat') RETURNING id`,
        [req.user.sub]
      );
      convId = conv.rows[0].id;
    }

    await pool.query(
      `INSERT INTO messages (conversation_id, role, content) VALUES ($1, 'user', $2)`,
      [convId, body.message]
    );

    const [memories, goals, emotion, recent] = await Promise.all([
      pool.query(
        `SELECT content, type FROM memories WHERE user_id = $1 AND importance >= 0.5 ORDER BY created_at DESC LIMIT 5`,
        [req.user.sub]
      ),
      pool.query("SELECT title, streak, progress FROM goals WHERE user_id = $1", [req.user.sub]),
      pool.query("SELECT mood FROM emotional_states WHERE user_id = $1 ORDER BY recorded_at DESC LIMIT 1", [req.user.sub]),
      pool.query(
        `SELECT content FROM messages WHERE conversation_id = $1 ORDER BY created_at DESC LIMIT 4`,
        [convId]
      ),
    ]);

    const systemMsg = {
      role: "system",
      content: `You are Jarvis, an AI accountability companion. Be warm but direct. Keep responses 2-3 sentences. User context: goals=${JSON.stringify(goals.rows)}, mood=${emotion.rows[0]?.mood || "unknown"}, memories=${JSON.stringify(memories.rows)}`,
    };

    const recentMessages = recent.rows.reverse().map((r: any) => ({
      role: "user" as const,
      content: r.content,
    }));

    const response = await callLLM([systemMsg, ...recentMessages]);

    await pool.query(
      `INSERT INTO messages (conversation_id, role, content) VALUES ($1, 'assistant', $2)`,
      [convId, response]
    );

    reply.send({ reply: response, conversation_id: convId });
  });

  app.get("/api/v1/chat/history/:conversationId", async (req, reply) => {
    const { conversationId } = req.params as { conversationId: string };
    const result = await pool.query(
      `SELECT role, content, created_at FROM messages WHERE conversation_id = $1 ORDER BY created_at ASC`,
      [conversationId]
    );
    reply.send({ messages: result.rows });
  });
}
