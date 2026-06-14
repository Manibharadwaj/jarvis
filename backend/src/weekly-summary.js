// ── Weekly AI-generated summary worker ─────────────────────────────────────────
// Runs every Sunday at 11:30 PM IST (18:00 UTC).
// For each user: aggregates the past 7 days of daily_log data,
// uses the LLM to write a narrative summary with insights, and
// saves it to the daily_summaries table (already in the schema).

import cron from 'node-cron';
import pg from 'pg';
import crypto from 'crypto';

const { Pool } = pg;

const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || 'https://ollama.com/v1';
const OLLAMA_KEY = process.env.OLLAMA_API_KEY || '';
const MODEL_NAME = process.env.OLLAMA_MODEL || 'gemma3:12b';
const TZ = 'Asia/Kolkata';

/**
 * Generate a weekly summary for a specific user.
 * @param {string} userId - The user's profile ID
 * @param {pg.Pool} pool - Database pool
 * @returns {{ ok: boolean, summary?: string, key_points?: string[] }}
 */
export async function generateWeeklySummary(userId, pool) {
  const weekAgo = "(NOW() AT TIME ZONE 'Asia/Kolkata' - INTERVAL '7 days')::date";
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";

  // 1. Aggregate daily_log data for the past 7 days
  const { rows: dailyLogs } = await pool.query(
    `SELECT date, food_calories, food_target, food_notes,
            gym_done, gym_protein, gym_creatine,
            code_done, code_notes,
            office_in_time, office_out_time,
            books_title, books_pages, books_insights,
            day_score, day_notes, hydration_glasses
     FROM public.daily_log
     WHERE user_id = $1 AND date >= ${weekAgo}
     ORDER BY date ASC`,
    [userId]
  );

  // 2. Get call stats for the week
  const { rows: callStats } = await pool.query(
    `SELECT
       COUNT(*) as total_calls,
       COUNT(*) FILTER (WHERE status = 'ended' OR status = 'connected') as answered_calls,
       COUNT(*) FILTER (WHERE status = 'missed' OR status = 'disconnected') as missed_calls
     FROM public.call_logs
     WHERE user_id = $1 AND started_at >= NOW() - INTERVAL '7 days'`,
    [userId]
  );

  // 3. Get user name
  const { rows: profileRows } = await pool.query(
    'SELECT name FROM public.profiles WHERE id = $1',
    [userId]
  );
  const userName = profileRows[0]?.name || 'sir';

  // If no daily logs, nothing to summarize
  if (dailyLogs.length === 0) {
    return { ok: false, message: 'No daily logs found for the past week' };
  }

  // 4. Build a data summary for the LLM
  const daysWithData = dailyLogs.length;
  const totalDays = 7;
  const daysMissed = totalDays - daysWithData;

  // Aggregate stats
  const gymDays = dailyLogs.filter(d => d.gym_done === true).length;
  const codeDays = dailyLogs.filter(d => d.code_done === true).length;
  const avgScore = dailyLogs.filter(d => d.day_score != null).length > 0
    ? (dailyLogs.filter(d => d.day_score != null).reduce((s, d) => s + d.day_score, 0) /
       dailyLogs.filter(d => d.day_score != null).length).toFixed(1)
    : null;
  const avgCalories = dailyLogs.filter(d => d.food_calories != null && d.food_calories > 0).length > 0
    ? Math.round(dailyLogs.filter(d => d.food_calories > 0).reduce((s, d) => s + d.food_calories, 0) /
      dailyLogs.filter(d => d.food_calories > 0).length)
    : null;
  const avgHydration = dailyLogs.filter(d => d.hydration_glasses != null).length > 0
    ? (dailyLogs.filter(d => d.hydration_glasses != null).reduce((s, d) => s + d.hydration_glasses, 0) /
       dailyLogs.filter(d => d.hydration_glasses != null).length).toFixed(1)
    : null;

  const callInfo = callStats[0] || {};
  const totalCalls = parseInt(callInfo.total_calls) || 0;
  const answeredCalls = parseInt(callInfo.answered_calls) || 0;
  const missedCalls = parseInt(callInfo.missed_calls) || 0;

  // Format individual day logs
  const dayLogs = dailyLogs.map(d => {
    const parts = [`${d.date}:`];
    if (d.gym_done === true) parts.push('gym ✓');
    if (d.gym_done === false) parts.push('gym ✗');
    if (d.food_calories) parts.push(`${d.food_calories} cal`);
    if (d.code_done === true) parts.push('code ✓');
    if (d.day_score) parts.push(`score ${d.day_score}/10`);
    if (d.hydration_glasses) parts.push(`${d.hydration_glasses} glasses water`);
    return parts.join(' ');
  }).join('\n');

  // 5. Call the LLM to generate a narrative summary
  const summaryPrompt = `You are J.A.R.V.I.S., an AI accountability companion. Write a weekly summary for ${userName}.

Here is their data for the past week (${daysWithData} days with data, ${daysMissed} days missed):

${dayLogs}

Overall stats:
- Gym days: ${gymDays}/${totalDays}
- Code days: ${codeDays}/${totalDays}
- Average day score: ${avgScore || 'N/A'}/10
- Average calories: ${avgCalories || 'N/A'}/day (target: 3000)
- Average hydration: ${avgHydration || 'N/A'}/8 glasses/day
- Calls answered: ${answeredCalls}/${totalCalls} (${missedCalls} missed)

Write a concise weekly summary (3-4 sentences) that:
1. Highlights what went well
2. Notes what needs improvement
3. Suggests one specific focus for next week
4. Includes their streak or consistency

Be direct, encouraging, and specific. Use data. No fluff. Maximum 200 words.`;

  const headers = { 'Content-Type': 'application/json' };
  if (OLLAMA_KEY) headers['Authorization'] = `Bearer ${OLLAMA_KEY}`;

  try {
    const resp = await fetch(`${OLLAMA_BASE_URL}/chat/completions`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: MODEL_NAME,
        messages: [{ role: 'user', content: summaryPrompt }],
        stream: false,
        temperature: 0.7,
        max_tokens: 300,
      }),
      signal: AbortSignal.timeout(60_000),
    });

    if (!resp.ok) {
      const body = await resp.text().catch(() => '');
      console.error(`[WeeklySummary] LLM error ${resp.status}: ${body.slice(0, 200)}`);
      return { ok: false, message: `LLM error: ${resp.status}` };
    }

    const data = await resp.json();
    const summaryText = (data.choices?.[0]?.message?.content || '').trim();

    if (!summaryText) {
      return { ok: false, message: 'LLM returned empty summary' };
    }

    // 6. Extract 3-5 key points from the summary
    const keyPointsPrompt = `Extract 3-5 key bullet points from this weekly summary. Each bullet point should be short (under 10 words). Return ONLY the bullet points, one per line, no numbering, no prefix.

${summaryText}`;

    let keyPoints = [];
    try {
      const kpResp = await fetch(`${OLLAMA_BASE_URL}/chat/completions`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          model: MODEL_NAME,
          messages: [{ role: 'user', content: keyPointsPrompt }],
          stream: false,
          temperature: 0.3,
          max_tokens: 100,
        }),
        signal: AbortSignal.timeout(30_000),
      });

      if (kpResp.ok) {
        const kpData = await kpResp.json();
        const kpText = (kpData.choices?.[0]?.message?.content || '').trim();
        keyPoints = kpText.split('\n').map(s => s.replace(/^[-•*]\s*/, '').trim()).filter(Boolean).slice(0, 5);
      }
    } catch {
      // Key points are optional — move on
    }

    // 7. Save to daily_summaries table
    await pool.query(
      `INSERT INTO public.daily_summaries (user_id, date, summary_text, key_points, mood_trend, tasks_completed, tasks_created, call_count)
       VALUES ($1, ${today}, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (user_id, date) DO UPDATE SET
         summary_text = EXCLUDED.summary_text,
         key_points = EXCLUDED.key_points,
         mood_trend = EXCLUDED.mood_trend,
         tasks_completed = EXCLUDED.tasks_completed,
         tasks_created = EXCLUDED.tasks_created,
         call_count = EXCLUDED.call_count`,
      [
        userId,
        summaryText,
        keyPoints,
        avgScore ? (parseFloat(avgScore) >= 7 ? 'improving' : parseFloat(avgScore) >= 5 ? 'stable' : 'declining') : null,
        dailyLogs.filter(d => d.gym_done === true || d.code_done === true).length,
        0,
        totalCalls,
      ]
    );

    console.log(`[WeeklySummary] Generated summary for user ${userId}: ${summaryText.slice(0, 80)}...`);
    return { ok: true, summary: summaryText, key_points: keyPoints };

  } catch (err) {
    console.error(`[WeeklySummary] Error for user ${userId}:`, err.message);
    return { ok: false, message: err.message };
  }
}

/**
 * Generate weekly summaries for all users.
 */
export async function generateAllWeeklySummaries(pool) {
  console.log('[WeeklySummary] Starting weekly summary generation');

  const { rows: users } = await pool.query('SELECT id, name FROM public.profiles');

  for (const user of users) {
    try {
      const result = await generateWeeklySummary(user.id, pool);
      if (result.ok) {
        console.log(`[WeeklySummary] ✓ User ${user.name || user.id}: summary generated`);
      } else {
        console.log(`[WeeklySummary] ⊘ User ${user.name || user.id}: ${result.message}`);
      }
    } catch (err) {
      console.error(`[WeeklySummary] Failed for user ${user.id}:`, err.message);
    }
  }

  console.log('[WeeklySummary] Complete');
}

/**
 * Start the weekly cron scheduler.
 */
export function startWeeklySummaryScheduler(pool) {
  // Every Sunday at 11:30 PM IST = 18:00 UTC
  cron.schedule('0 18 * * 0', async () => {
    console.log('[WeeklySummary] Cron triggered — generating weekly summaries');
    await generateAllWeeklySummaries(pool);
  }, { timezone: TZ });

  console.log('[WeeklySummary] Scheduler armed (Sundays 11:30 PM IST)');
}

/**
 * Mount the API endpoint for getting the latest weekly summary.
 */
export function mountWeeklySummaryRoutes(app, pool) {
  // Timing-safe string compare (reused from server.js)
  function timingSafeEqualStr(a, b) {
    if (typeof a !== 'string' || typeof b !== 'string') return false;
    const aH = crypto.createHash('sha256').update(a).digest();
    const bH = crypto.createHash('sha256').update(b).digest();
    return crypto.timingSafeEqual(aH, bH);
  }

  // Auth: accept either agent secret or app key
  function summaryAuth(req, res, next) {
    const AGENT_SECRET = process.env.AGENT_SECRET || '';
    const APP_API_KEY = process.env.APP_API_KEY || '';
    const agentOk = req.headers['x-agent-secret'] && timingSafeEqualStr(req.headers['x-agent-secret'], AGENT_SECRET);
    if (agentOk) return next();
    if (!APP_API_KEY) return res.status(503).json({ error: 'App API key not configured' });
    if (!timingSafeEqualStr(req.headers['x-app-key'], APP_API_KEY)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
  }

  // GET /api/weekly-summary — get latest weekly summary
  app.get('/api/weekly-summary', summaryAuth, async (req, res) => {
    try {
      // Resolve user: from X-User-Id header or first profile
      let userId = req.headers['x-user-id'];
      if (!userId) {
        const r = await pool.query('SELECT id FROM public.profiles LIMIT 1');
        userId = r.rows[0]?.id;
      }
      if (!userId) return res.status(404).json({ error: 'No user found' });

      const { rows } = await pool.query(
        `SELECT id, date, summary_text, key_points, mood_trend, tasks_completed, call_count
         FROM public.daily_summaries
         WHERE user_id = $1
         ORDER BY date DESC
         LIMIT 4`,
        [typeof userId === 'string' ? userId : await userId]
      );

      res.json({ summaries: rows });
    } catch (err) {
      console.error('[WeeklySummary] GET error:', err.message);
      res.status(500).json({ error: err.message });
    }
  });

  // POST /api/weekly-summary/generate — trigger manual generation
  app.post('/api/weekly-summary/generate', agentAuth, async (req, res) => {
    try {
      const userId = req.headers['x-user-id'] || null;

      if (userId) {
        const result = await generateWeeklySummary(userId, pool);
        return res.json(result);
      }

      // Generate for all users
      const result = await generateAllWeeklySummaries(pool);
      res.json({ ok: true, message: 'Weekly summaries generated for all users' });
    } catch (err) {
      console.error('[WeeklySummary] Generate error:', err.message);
      res.status(500).json({ error: err.message });
    }
  });
}