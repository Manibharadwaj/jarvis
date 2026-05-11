import { FastifyInstance } from "fastify";
import { incrementStreak, resetStreak, getAccountabilityReport } from "../services/accountability.js";

export async function accountabilityRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.get("/api/v1/accountability", async (req, reply) => {
    const report = await getAccountabilityReport(req.user.sub);
    reply.send(report);
  });

  app.post("/api/v1/accountability/checkin/:goalId", async (req, reply) => {
    const { goalId } = req.params as { goalId: string };
    const streak = await incrementStreak(req.user.sub, goalId);
    reply.send({ streak });
  });

  app.post("/api/v1/accountability/miss/:goalId", async (req, reply) => {
    const { goalId } = req.params as { goalId: string };
    await resetStreak(req.user.sub, goalId);
    reply.send({ ok: true });
  });
}
