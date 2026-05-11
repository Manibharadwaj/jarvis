import { FastifyInstance } from "fastify";
import { pool } from "../config/database.js";
import { redis } from "../config/redis.js";

export async function healthRoutes(app: FastifyInstance) {
  app.get("/api/v1/health", async (_req, reply) => {
    let dbStatus = "ok";
    let redisStatus = "ok";

    try {
      await pool.query("SELECT 1");
    } catch {
      dbStatus = "error";
    }

    try {
      await redis.ping();
    } catch {
      redisStatus = "error";
    }

    const healthy = dbStatus === "ok" && redisStatus === "ok";

    reply.code(healthy ? 200 : 503).send({
      status: healthy ? "healthy" : "degraded",
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      checks: {
        database: dbStatus,
        redis: redisStatus,
      },
    });
  });
}
