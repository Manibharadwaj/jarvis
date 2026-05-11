import { Job, Worker, Queue } from "bullmq";
import { redis } from "../config/redis.js";
import { sendPushNotification, getFcmToken } from "../services/notification.js";
import { pool } from "../config/database.js";

export const pushQueue = new Queue("push-notifications", {
  connection: redis,
});

export async function schedulePushNotification(
  userId: string,
  title: string,
  body: string,
  scheduledFor: Date,
  data?: Record<string, string>
) {
  await pushQueue.add(
    "push",
    { userId, title, body, data },
    { delay: scheduledFor.getTime() - Date.now(), jobId: `${userId}-${Date.now()}` }
  );
}

export function createPushWorker() {
  return new Worker(
    "push-notifications",
    async (job: Job) => {
      const { userId, title, body, data } = job.data;
      const fcmToken = await getFcmToken(userId);
      if (!fcmToken) {
        console.warn(`No FCM token for user ${userId}, skipping push`);
        return;
      }
      await sendPushNotification(fcmToken, title, body, data);
    },
    { connection: redis }
  );
}

async function pollScheduledCalls() {
  const result = await pool.query(
    `SELECT id, user_id, call_type, scheduled_for
     FROM scheduled_calls
     WHERE status = 'pending' AND scheduled_for <= now()
       AND retry_count < 5
     ORDER BY scheduled_for ASC
     LIMIT 10`
  );

  for (const row of result.rows) {
    await schedulePushNotification(
      row.user_id,
      "Jarvis Check-In",
      `Time for your ${row.call_type.replace("-", " ")}. Tap to answer.`,
      new Date(),
      { call_id: row.id, call_type: row.call_type, type: "voice" }
    );

    await pool.query(
      `UPDATE scheduled_calls SET retry_count = retry_count + 1 WHERE id = $1`,
      [row.id]
    );
  }
}

setInterval(pollScheduledCalls, 60_000);
