// ── Nightly memory consolidation scheduler ─────────────────────────────────────
// Runs at 1 AM IST (19:30 UTC) every day.
// For each user, processes un-summarized calls and extracts:
//   - Key facts → user_context (key-value)
//   - Episodic memories → memories table (with embeddings)

import cron from 'node-cron';
import { consolidateMemoriesForUser } from './memory.js';

const TZ = 'Asia/Kolkata';

export function startConsolidationScheduler(pool) {
  // 1 AM IST = 19:30 UTC
  cron.schedule('30 19 * * *', async () => {
    console.log('[Consolidation] Starting nightly memory consolidation');
    try {
      const { rows: users } = await pool.query('SELECT id FROM public.profiles');
      for (const user of users) {
        try {
          const result = await consolidateMemoriesForUser(user.id, pool);
          console.log(`[Consolidation] User ${user.id}: ${result.processed} calls, ${result.facts_extracted} facts, ${result.memories_created} memories`);
        } catch (err) {
          console.error(`[Consolidation] Failed for user ${user.id}:`, err.message);
        }
      }
      console.log('[Consolidation] Nightly consolidation complete');
    } catch (err) {
      console.error('[Consolidation] Scheduler error:', err.message);
    }
  }, { timezone: TZ });

  console.log('[Consolidation] Scheduler armed (1 AM IST nightly)');
}