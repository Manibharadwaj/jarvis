import { FastifyInstance } from "fastify";
import z from "zod";
import { createRoomAndToken } from "../services/livekit.js";
import { pool } from "../config/database.js";

const startCallSchema = z.object({
  call_type: z.enum(["check-in", "wake-up", "evening-review", "follow-up"]).default("check-in"),
});

export async function voiceRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.post("/api/v1/voice/start", async (req, reply) => {
    const body = startCallSchema.parse(req.body);
    const { room, token, url } = await createRoomAndToken(req.user.sub);

    const result = await pool.query(
      `INSERT INTO conversations (user_id, call_type) VALUES ($1, $2) RETURNING id`,
      [req.user.sub, body.call_type]
    );

    reply.send({
      room,
      token,
      url,
      conversation_id: result.rows[0].id,
    });
  });

  app.post("/api/v1/voice/end", async (req, reply) => {
    const { conversation_id } = req.body as { conversation_id: string };

    await pool.query(
      `UPDATE conversations SET ended_at = now() WHERE id = $1 AND user_id = $2`,
      [conversation_id, req.user.sub]
    );

    reply.send({ ok: true });
  });
}
