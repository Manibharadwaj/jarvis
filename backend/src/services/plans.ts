import { pool } from "../config/database.js";

export async function createDailyPlan(
  userId: string,
  morningIntent?: string,
  priorities?: string[],
  commitments?: string[]
) {
  const result = await pool.query(
    `INSERT INTO daily_plans (user_id, morning_intent, priorities, commitments)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (user_id, date) DO UPDATE
       SET morning_intent = COALESCE($2, daily_plans.morning_intent),
           priorities = COALESCE($3, daily_plans.priorities),
           commitments = COALESCE($4, daily_plans.commitments),
           updated_at = now()
     RETURNING *`,
    [userId, morningIntent || null, priorities ? JSON.stringify(priorities) : null, commitments ? JSON.stringify(commitments) : null]
  );
  return result.rows[0];
}

export async function submitEveningReview(userId: string, review: string) {
  const plan = await pool.query(
    `UPDATE daily_plans
     SET evening_review = $2, updated_at = now()
     WHERE user_id = $1 AND date = CURRENT_DATE
     RETURNING *`,
    [userId, review]
  );

  if (plan.rows.length === 0) {
    const result = await pool.query(
      `INSERT INTO daily_plans (user_id, evening_review) VALUES ($1, $2) RETURNING *`,
      [userId, review]
    );
    return result.rows[0];
  }

  return plan.rows[0];
}

export async function getTodayPlan(userId: string) {
  const result = await pool.query(
    "SELECT * FROM daily_plans WHERE user_id = $1 AND date = CURRENT_DATE",
    [userId]
  );
  return result.rows[0] || null;
}

export async function getPlanHistory(userId: string, days: number = 7) {
  const result = await pool.query(
    `SELECT * FROM daily_plans
     WHERE user_id = $1 AND date >= CURRENT_DATE - make_interval(days => $2)
     ORDER BY date DESC`,
    [userId, days]
  );
  return result.rows;
}
