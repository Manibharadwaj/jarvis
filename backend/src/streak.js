// ── Streak tracking + accountability gamification ────────────────────────────────
// Calculates consecutive-day streaks from call_logs and daily_log data.
// Exposes GET /api/streak endpoint for the app.

import pg from 'pg';

/**
 * Calculate streak data for a user.
 * - Call streak: consecutive days with at least 1 answered call
 * - Gym streak: consecutive days with gym_done = true
 * - Code streak: consecutive days with code_done = true
 * - Overall streak: consecutive days with day_score >= 7
 * - Best streak: all-time best call streak
 * - Badges: unlocked at 7, 14, 30, 60, 100 days
 */
export async function calculateStreak(userId, pool) {
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";

  // 1. Call streak — consecutive days with at least 1 answered/ended call
  const { rows: callDays } = await pool.query(
    `SELECT DISTINCT (started_at AT TIME ZONE 'Asia/Kolkata')::date AS day
     FROM public.call_logs
     WHERE user_id = $1
       AND status IN ('ended', 'connected')
       AND started_at > NOW() - INTERVAL '120 days'
     ORDER BY day DESC`,
    [userId]
  );

  const callStreak = countConsecutive(callDays.map(r => r.day));

  // 2. Best call streak ever
  const bestCallStreak = countBestStreak(callDays.map(r => r.day));

  // 3. Gym streak — consecutive days with gym_done = true
  const { rows: gymDays } = await pool.query(
    `SELECT DISTINCT date AS day
     FROM public.daily_log
     WHERE user_id = $1 AND gym_done = true
       AND date > ${today} - INTERVAL '120 days'
     ORDER BY day DESC`,
    [userId]
  );
  const gymStreak = countConsecutive(gymDays.map(r => new Date(r.day)));

  // 4. Code streak — consecutive days with code_done = true
  const { rows: codeDays } = await pool.query(
    `SELECT DISTINCT date AS day
     FROM public.daily_log
     WHERE user_id = $1 AND code_done = true
       AND date > ${today} - INTERVAL '120 days'
     ORDER BY day DESC`,
    [userId]
  );
  const codeStreak = countConsecutive(codeDays.map(r => new Date(r.day)));

  // 5. Score streak — consecutive days with day_score >= 7
  const { rows: scoreDays } = await pool.query(
    `SELECT DISTINCT date AS day
     FROM public.daily_log
     WHERE user_id = $1 AND day_score >= 7
       AND date > ${today} - INTERVAL '120 days'
     ORDER BY day DESC`,
    [userId]
  );
  const scoreStreak = countConsecutive(scoreDays.map(r => new Date(r.day)));

  // 6. Badges
  const badges = [];
  const badgeThresholds = [7, 14, 30, 60, 100];
  for (const t of badgeThresholds) {
    if (callStreak >= t) badges.push({ type: 'call_streak', days: t, label: `${t}-Day Call Streak` });
    if (gymStreak >= t) badges.push({ type: 'gym_streak', days: t, label: `${t}-Day Gym Streak` });
    if (codeStreak >= t) badges.push({ type: 'code_streak', days: t, label: `${t}-Day Code Streak` });
  }

  return {
    call_streak: callStreak,
    best_call_streak: bestCallStreak,
    gym_streak: gymStreak,
    code_streak: codeStreak,
    score_streak: scoreStreak,
    badges,
  };
}

/**
 * Count consecutive days going backwards from today.
 * Expects dates sorted DESC (most recent first).
 */
function countConsecutive(dates) {
  if (!dates.length) return 0;

  let streak = 0;
  let expected = new Date();
  expected.setHours(0, 0, 0, 0); // Today

  for (const d of dates) {
    const day = new Date(d);
    day.setHours(0, 0, 0, 0);

    const diffDays = Math.round((expected - day) / (1000 * 60 * 60 * 24));

    if (diffDays === 0) {
      // Today counts
      streak++;
      expected.setDate(expected.getDate() - 1);
    } else if (diffDays === 1) {
      // Missed today but yesterday is there — still counts (grace period)
      streak++;
      expected = new Date(day);
      expected.setDate(expected.getDate() - 1);
    } else if (diffDays === streak + 1) {
      // Next consecutive day
      streak++;
      expected = new Date(day);
      expected.setDate(expected.getDate() - 1);
    } else {
      break;
    }
  }

  return streak;
}

/**
 * Count the all-time best streak from a list of dates (sorted DESC).
 */
function countBestStreak(dates) {
  if (!dates.length) return 0;

  // Sort ascending for easier counting
  const sorted = dates.map(d => {
    const day = new Date(d);
    day.setHours(0, 0, 0, 0);
    return day.getTime();
  }).sort((a, b) => a - b);

  let best = 1;
  let current = 1;
  const oneDay = 24 * 60 * 60 * 1000;

  for (let i = 1; i < sorted.length; i++) {
    const diff = sorted[i] - sorted[i - 1];
    if (diff === oneDay) {
      current++;
      best = Math.max(best, current);
    } else if (diff > oneDay) {
      current = 1;
    }
    // Same day = skip
  }

  return best;
}

/**
 * Mount streak API routes.
 */
export function mountStreakRoutes(app, pool) {
  app.get('/api/streak', async (req, res) => {
    // Auth: check agent secret or app key
    const AGENT_SECRET = process.env.AGENT_SECRET || '';
    const APP_API_KEY = process.env.APP_API_KEY || '';
    const crypto = await import('crypto');
    function tsEq(a, b) {
      if (typeof a !== 'string' || typeof b !== 'string') return false;
      return crypto.timingSafeEqual(
        crypto.createHash('sha256').update(a).digest(),
        crypto.createHash('sha256').update(b).digest()
      );
    }

    const agentOk = req.headers['x-agent-secret'] && tsEq(req.headers['x-agent-secret'], AGENT_SECRET);
    const appOk = APP_API_KEY && req.headers['x-app-key'] && tsEq(req.headers['x-app-key'], APP_API_KEY);
    if (!agentOk && !appOk) return res.status(401).json({ error: 'Unauthorized' });

    try {
      // Resolve user
      let userId = req.headers['x-user-id'];
      if (!userId) {
        const r = await pool.query('SELECT id FROM public.profiles LIMIT 1');
        userId = r.rows[0]?.id;
      }
      if (!userId) return res.status(404).json({ error: 'No user found' });

      const streak = await calculateStreak(userId, pool);
      res.json(streak);
    } catch (err) {
      console.error('/api/streak:', err.message);
      res.status(500).json({ error: err.message });
    }
  });
}