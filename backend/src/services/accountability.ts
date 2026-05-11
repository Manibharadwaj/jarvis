import { pool } from "../config/database.js";

export async function calculateStreak(userId: string, goalId: string): Promise<number> {
  const result = await pool.query(
    `SELECT streak FROM goals WHERE id = $1 AND user_id = $2`,
    [goalId, userId]
  );
  return result.rows[0]?.streak || 0;
}

export async function incrementStreak(userId: string, goalId: string) {
  const result = await pool.query(
    `UPDATE goals SET streak = streak + 1, updated_at = now()
     WHERE id = $1 AND user_id = $2
     RETURNING streak`,
    [goalId, userId]
  );
  return result.rows[0]?.streak || 1;
}

export async function resetStreak(userId: string, goalId: string) {
  await pool.query(
    `UPDATE goals SET streak = 0, updated_at = now()
     WHERE id = $1 AND user_id = $2`,
    [goalId, userId]
  );
}

export async function calculateAccountabilityScore(userId: string): Promise<number> {
  const goals = await pool.query(
    "SELECT streak, progress FROM goals WHERE user_id = $1",
    [userId]
  );

  if (goals.rows.length === 0) return 0;

  const totalScore = goals.rows.reduce((sum, g) => {
    return sum + (g.streak * 10) + (g.progress * 50);
  }, 0);

  const maxPossible = goals.rows.length * 60;
  return Math.round((totalScore / maxPossible) * 100);
}

export async function getAccountabilityReport(userId: string) {
  const score = await calculateAccountabilityScore(userId);

  const plans = await pool.query(
    `SELECT date, accountability_score, evening_review
     FROM daily_plans
     WHERE user_id = $1 AND date >= CURRENT_DATE - 7
     ORDER BY date DESC`,
    [userId]
  );

  const goals = await pool.query(
    "SELECT title, streak, progress FROM goals WHERE user_id = $1 ORDER BY streak DESC",
    [userId]
  );

  const calls = await pool.query(
    `SELECT call_type, status, scheduled_for::date as date
     FROM scheduled_calls
     WHERE user_id = $1 AND scheduled_for >= CURRENT_DATE - 7
     ORDER BY scheduled_for DESC`,
    [userId]
  );

  return { score, plans: plans.rows, goals: goals.rows, calls: calls.rows };
}

export async function markMissedCalls() {
  await pool.query(
    `UPDATE scheduled_calls
     SET status = 'missed'
     WHERE status = 'pending' AND scheduled_for < now() AND retry_count >= 5`
  );
}

export async function processStreaks() {
  const stale = await pool.query(
    `UPDATE goals
     SET streak = 0
     WHERE streak > 0 AND updated_at < now() - interval '3 days'
     RETURNING id, user_id, title`
  );

  for (const goal of stale.rows) {
    await pool.query(
      `INSERT INTO scheduled_calls (user_id, call_type, scheduled_for)
       VALUES ($1, 'follow-up', now() + interval '15 minutes')`,
      [goal.user_id]
    );
  }

  return stale.rows;
}
