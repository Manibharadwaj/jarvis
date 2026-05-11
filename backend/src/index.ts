import Fastify from "fastify";
import cors from "@fastify/cors";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import { env } from "./config/env.js";
import { healthRoutes } from "./routes/health.js";
import { authRoutes } from "./routes/auth.js";
import { goalRoutes } from "./routes/goals.js";
import { notificationRoutes } from "./routes/notifications.js";
import { voiceRoutes } from "./routes/voice.js";
import { memoryRoutes } from "./routes/memories.js";
import { emotionRoutes } from "./routes/emotions.js";
import { relationshipRoutes } from "./routes/relationship.js";
import { planRoutes } from "./routes/plans.js";
import { accountabilityRoutes } from "./routes/accountability.js";
import { chatRoutes } from "./routes/chat.js";
import { runMigrations } from "./migrations/001_initial.js";
import { createPushWorker } from "./jobs/push-scheduler.js";
import { createCallWorker, callQueue } from "./jobs/call-scheduler.js";
import { createPlanWorker } from "./jobs/daily-plan.js";
import { createConsolidationWorker, scheduleConsolidation } from "./jobs/memory-consolidation.js";
import { processStreaks, markMissedCalls } from "./services/accountability.js";

const app = Fastify({
  logger: true,
});

await app.register(cors);
await app.register(jwt, { secret: env.JWT_SECRET });
await app.register(rateLimit, { max: 100, timeWindow: "1 minute" });

await app.register(healthRoutes);
await app.register(authRoutes);
await app.register(goalRoutes);
await app.register(notificationRoutes);
await app.register(voiceRoutes);
await app.register(memoryRoutes);
await app.register(emotionRoutes);
await app.register(relationshipRoutes);
await app.register(planRoutes);
await app.register(accountabilityRoutes);
await app.register(chatRoutes);

if (env.NODE_ENV !== "production") {
  await runMigrations();
}

const pushWorker = createPushWorker();
pushWorker.on("error", (err) => app.log.error(err));

const callWorker = createCallWorker();
callWorker.on("error", (err) => app.log.error(err));

const planWorker = createPlanWorker();
planWorker.on("error", (err) => app.log.error(err));

const consolidationWorker = createConsolidationWorker();
consolidationWorker.on("error", (err) => app.log.error(err));

if (env.NODE_ENV !== "production") {
  await scheduleConsolidation();
}

setInterval(async () => {
  try {
    await markMissedCalls();
    const stale = await processStreaks();
    if (stale.length > 0) {
      app.log.info(`Reset ${stale.length} stale streaks`);
    }
  } catch (err) {
    app.log.error({ err }, "Streak processing error");
  }
}, 5 * 60 * 1000);

try {
  await app.listen({ port: env.PORT, host: "0.0.0.0" });
  console.log(`Jarvis backend running on port ${env.PORT}`);
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
