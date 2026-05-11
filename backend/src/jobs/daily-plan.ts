import { Job, Worker, Queue } from "bullmq";
import { redis } from "../config/redis.js";
import { pool } from "../config/database.js";
import { scheduleMorningCall, scheduleEveningReview, scheduleCall } from "./call-scheduler.js";

export const planQueue = new Queue("daily-plans", { connection: redis });

export async function scheduleDailyPlanJobs(userId: string, wakeTime: string, sleepTime: string) {
  await scheduleMorningCall(userId, wakeTime);
  await scheduleEveningReview(userId, sleepTime);

  const now = new Date();
  const midday = new Date(now);
  midday.setHours(12, 0, 0, 0);
  if (midday <= now) midday.setDate(midday.getDate() + 1);

  await scheduleCall(userId, "check-in", midday);
}

export function createPlanWorker() {
  return new Worker(
    "daily-plans",
    async (job: Job) => {
      const { type, userId, title, body, data } = job.data;

      if (type === "push") {
        const { schedulePushNotification } = await import("./push-scheduler.js");
        await schedulePushNotification(userId, title, body, new Date(), data);
      }
    },
    { connection: redis }
  );
}

export async function enqueuePushNotification(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>
) {
  await planQueue.add("push", { type: "push", userId, title, body, data });
}
