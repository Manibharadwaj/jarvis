import { FastifyInstance } from "fastify";
import z from "zod";
import { createDailyPlan, submitEveningReview, getTodayPlan, getPlanHistory } from "../services/plans.js";

const morningPlanSchema = z.object({
  morning_intent: z.string().max(500).optional(),
  priorities: z.array(z.string().max(200)).max(10).optional(),
  commitments: z.array(z.string().max(200)).max(10).optional(),
});

const eveningReviewSchema = z.object({
  review: z.string().min(1).max(2000),
});

export async function planRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.post("/api/v1/plans/morning", async (req, reply) => {
    const body = morningPlanSchema.parse(req.body);
    const plan = await createDailyPlan(req.user.sub, body.morning_intent, body.priorities, body.commitments);
    reply.send({ plan });
  });

  app.post("/api/v1/plans/evening-review", async (req, reply) => {
    const body = eveningReviewSchema.parse(req.body);
    const plan = await submitEveningReview(req.user.sub, body.review);
    reply.send({ plan });
  });

  app.get("/api/v1/plans/today", async (req, reply) => {
    const plan = await getTodayPlan(req.user.sub);
    reply.send({ plan });
  });

  app.get("/api/v1/plans/history", async (req, reply) => {
    const { days } = req.query as { days?: string };
    const history = await getPlanHistory(req.user.sub, days ? parseInt(days) : 7);
    reply.send({ history });
  });
}
