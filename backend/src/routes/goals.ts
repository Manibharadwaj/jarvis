import { FastifyInstance } from "fastify";
import z from "zod";
import { createGoal, getGoals, getGoalById, updateGoal, deleteGoal } from "../services/goals.js";

const createGoalSchema = z.object({
  title: z.string().min(1).max(500),
  category: z.string().min(1).max(100),
  frequency: z.string().min(1).max(50),
  check_in_times: z.array(z.string()).default([]),
});

const updateGoalSchema = z.object({
  title: z.string().min(1).max(500).optional(),
  category: z.string().min(1).max(100).optional(),
  frequency: z.string().min(1).max(50).optional(),
  check_in_times: z.array(z.string()).optional(),
  progress: z.number().min(0).max(1).optional(),
  streak: z.number().min(0).optional(),
});

export async function goalRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.post("/api/v1/goals", async (req, reply) => {
    const body = createGoalSchema.parse(req.body);
    const goal = await createGoal(req.user.sub, body.title, body.category, body.frequency, body.check_in_times);
    reply.code(201).send({ goal });
  });

  app.get("/api/v1/goals", async (req, reply) => {
    const goals = await getGoals(req.user.sub);
    reply.send({ goals });
  });

  app.get("/api/v1/goals/:id", async (req, reply) => {
    const { id } = req.params as { id: string };
    const goal = await getGoalById(req.user.sub, id);
    if (!goal) {
      reply.code(404).send({ error: "Goal not found" });
      return;
    }
    reply.send({ goal });
  });

  app.patch("/api/v1/goals/:id", async (req, reply) => {
    const { id } = req.params as { id: string };
    const body = updateGoalSchema.parse(req.body);
    const goal = await updateGoal(req.user.sub, id, body);
    if (!goal) {
      reply.code(404).send({ error: "Goal not found" });
      return;
    }
    reply.send({ goal });
  });

  app.delete("/api/v1/goals/:id", async (req, reply) => {
    const { id } = req.params as { id: string };
    const deleted = await deleteGoal(req.user.sub, id);
    if (!deleted) {
      reply.code(404).send({ error: "Goal not found" });
      return;
    }
    reply.code(204).send();
  });
}
