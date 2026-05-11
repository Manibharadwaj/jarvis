import { Job, Worker, Queue } from "bullmq";
import { redis } from "../config/redis.js";
import { pool } from "../config/database.js";

export const consolidationQueue = new Queue("memory-consolidation", { connection: redis });

export async function scheduleConsolidation() {
  await consolidationQueue.add(
    "consolidate",
    {},
    { repeat: { pattern: "0 3 * * *" } }
  );
}

export function createConsolidationWorker() {
  return new Worker(
    "memory-consolidation",
    async (_job: Job) => {
      const lowImportance = await pool.query(
        `UPDATE memories
         SET importance = importance + 0.1
         WHERE importance < 0.3 AND created_at < now() - interval '7 days'
         RETURNING id`
      );

      const duplicateMemories = await pool.query(
        `DELETE FROM memories
         WHERE id IN (
           SELECT m1.id FROM memories m1
           JOIN memories m2 ON m1.user_id = m2.user_id
             AND m1.content = m2.content
             AND m1.id > m2.id
             AND m1.created_at > m2.created_at - interval '1 hour'
         )
         RETURNING id`
      );

      const staleRelationships = await pool.query(
        `UPDATE relationship_state
         SET rapport_level = GREATEST(0, rapport_level - 0.05)
         WHERE updated_at < now() - interval '14 days'`
      );

      return {
        boosted: lowImportance.rows.length,
        deduped: duplicateMemories.rows.length,
        decayed: staleRelationships.rowCount,
      };
    },
    { connection: redis }
  );
}
