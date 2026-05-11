import { Job, Worker, Queue } from "bullmq";
import { redis } from "../config/redis.js";
import { pool } from "../config/database.js";
import { schedulePushNotification } from "./push-scheduler.js";

export const callQueue = new Queue("scheduled-calls", { connection: redis });

const RETRY_INTERVALS = [2, 4, 8, 15, 15];
const TONE_TAGS = ["gentle", "firm", "concerned", "direct", "direct"];

export async function scheduleCall(
  userId: string,
  callType: string,
  scheduledFor: Date
) {
  const result = await pool.query(
    `INSERT INTO scheduled_calls (user_id, call_type, scheduled_for)
     VALUES ($1, $2, $3)
     RETURNING id, scheduled_for`,
    [userId, callType, scheduledFor]
  );

  const delay = scheduledFor.getTime() - Date.now();
  if (delay > 0) {
    await callQueue.add(
      "initiate-call",
      { callId: result.rows[0].id, userId, callType, retryCount: 0 },
      { delay, jobId: `call-${result.rows[0].id}` }
    );
  }

  return result.rows[0];
}

export function createCallWorker() {
  return new Worker(
    "scheduled-calls",
    async (job: Job) => {
      const { callId, userId, callType, retryCount } = job.data;

      if (retryCount >= 5) {
        await pool.query(
          `UPDATE scheduled_calls SET status = 'missed' WHERE id = $1`,
          [callId]
        );

        await schedulePushNotification(
          userId,
          "Jarvis - Missed Check-In",
          "I missed you today. Let's catch up when you can.",
          new Date(),
          { call_id: callId, type: "chat-fallback" }
        );
        return;
      }

      const toneIndex = Math.min(retryCount, TONE_TAGS.length - 1);
      const title = toneIndex === 0 ? "Jarvis Check-In" : `Jarvis (${TONE_TAGS[toneIndex]})`;
      const body = [
        "Time for our check-in. Tap to answer.",
        "I'm waiting. Tap to talk.",
        "This is your reminder. Don't skip.",
        "We need to talk. Tap in.",
        "Last call before I mark it missed.",
      ][toneIndex] || "Tap to answer.";

      await schedulePushNotification(userId, title, body, new Date(), {
        call_id: callId,
        call_type: callType,
        type: "voice",
      });

      const nextInterval = RETRY_INTERVALS[retryCount] || 15;
      const nextDelay = nextInterval * 60 * 1000;

      await callQueue.add(
        "initiate-call",
        { callId, userId, callType, retryCount: retryCount + 1 },
        { delay: nextDelay, jobId: `call-${callId}-retry-${retryCount + 1}` }
      );

      await pool.query(
        `UPDATE scheduled_calls
         SET retry_count = $2, retry_interval = $3
         WHERE id = $1`,
        [callId, retryCount + 1, nextInterval]
      );
    },
    { connection: redis }
  );
}

export async function scheduleMorningCall(userId: string, wakeTime: string) {
  const [hours, minutes] = wakeTime.split(":").map(Number);
  const now = new Date();
  const scheduled = new Date(now);
  scheduled.setHours(hours, minutes, 0, 0);

  if (scheduled <= now) {
    scheduled.setDate(scheduled.getDate() + 1);
  }

  return scheduleCall(userId, "wake-up", scheduled);
}

export async function scheduleEveningReview(userId: string, sleepTime: string) {
  const [hours, minutes] = sleepTime.split(":").map(Number);
  const now = new Date();
  const scheduled = new Date(now);
  scheduled.setHours(hours, minutes, 0, 0);

  if (scheduled <= now) {
    scheduled.setDate(scheduled.getDate() + 1);
  }

  return scheduleCall(userId, "evening-review", scheduled);
}
