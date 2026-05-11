import { pool } from "../config/database.js";

export async function createGoal(
  userId: string,
  title: string,
  category: string,
  frequency: string,
  checkInTimes: string[]
) {
  const result = await pool.query(
    `INSERT INTO goals (user_id, title, category, frequency, check_in_times)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [userId, title, category, frequency, JSON.stringify(checkInTimes)]
  );
  return result.rows[0];
}

export async function getGoals(userId: string) {
  const result = await pool.query(
    "SELECT * FROM goals WHERE user_id = $1 ORDER BY created_at DESC",
    [userId]
  );
  return result.rows;
}

export async function getGoalById(userId: string, goalId: string) {
  const result = await pool.query(
    "SELECT * FROM goals WHERE id = $1 AND user_id = $2",
    [goalId, userId]
  );
  return result.rows[0] || null;
}

export async function updateGoal(
  userId: string,
  goalId: string,
  updates: Partial<{
    title: string;
    category: string;
    frequency: string;
    check_in_times: string[];
    progress: number;
    streak: number;
  }>
) {
  const fields: string[] = [];
  const values: any[] = [];
  let idx = 1;

  for (const [key, value] of Object.entries(updates)) {
    if (value !== undefined) {
      fields.push(`${key} = $${idx++}`);
      values.push(key === "check_in_times" ? JSON.stringify(value) : value);
    }
  }

  if (fields.length === 0) return null;

  fields.push(`updated_at = now()`);
  values.push(goalId, userId);

  const result = await pool.query(
    `UPDATE goals SET ${fields.join(", ")} WHERE id = $${idx++} AND user_id = $${idx} RETURNING *`,
    values
  );
  return result.rows[0] || null;
}

export async function deleteGoal(userId: string, goalId: string) {
  const result = await pool.query(
    "DELETE FROM goals WHERE id = $1 AND user_id = $2 RETURNING id",
    [goalId, userId]
  );
  return result.rows.length > 0;
}
