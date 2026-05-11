import { FastifyInstance } from "fastify";
import z from "zod";
import { recordEmotion, getEmotionHistory, getLatestEmotion } from "../services/emotion.js";

const recordEmotionSchema = z.object({
  mood: z.string().min(1).max(50),
  energy: z.number().min(0).max(1).optional(),
  stress: z.number().min(0).max(1).optional(),
});

export async function emotionRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.post("/api/v1/emotions", async (req, reply) => {
    const body = recordEmotionSchema.parse(req.body);
    const emotion = await recordEmotion(req.user.sub, body.mood, body.energy, body.stress);
    reply.code(201).send({ emotion });
  });

  app.get("/api/v1/emotions", async (req, reply) => {
    const { days } = req.query as { days?: string };
    const history = await getEmotionHistory(req.user.sub, days ? parseInt(days) : 7);
    reply.send({ history });
  });

  app.get("/api/v1/emotions/latest", async (req, reply) => {
    const emotion = await getLatestEmotion(req.user.sub);
    if (!emotion) {
      reply.send({ emotion: null });
      return;
    }
    reply.send({ emotion });
  });
}
