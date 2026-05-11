import { FastifyInstance } from "fastify";
import z from "zod";
import { storeFcmToken } from "../services/notification.js";

const tokenSchema = z.object({
  fcm_token: z.string().min(1),
});

export async function notificationRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.post("/api/v1/notifications/register", async (req, reply) => {
    const body = tokenSchema.parse(req.body);
    await storeFcmToken(req.user.sub, body.fcm_token);
    reply.send({ ok: true });
  });
}
